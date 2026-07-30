// netstack.c — lwTCP/IP stack for RiscV WebSoC
// Single-file: Ethernet, ARP, IP, ICMP, TCP, HTTP
#include "inc/system.h"
#include "net_config.h"

// ── CPU FIFO registers ────────────────────────────────────────────────
#define REG_RD_EMPTY (*(volatile uint32_t*)(LCPU_BASE + 0x6000 * 4))
#define REG_RD_POP   (*(volatile uint32_t*)(LCPU_BASE + 0x6001 * 4))
#define REG_RD_LEN   (*(volatile uint32_t*)(LCPU_BASE + 0x6002 * 4))
#define REG_RD_REN   (*(volatile uint32_t*)(LCPU_BASE + 0x6003 * 4))
#define REG_RD_ADDR  (*(volatile uint32_t*)(LCPU_BASE + 0x6004 * 4))
#define REG_RD_DATA  (*(volatile uint32_t*)(LCPU_BASE + 0x6005 * 4))
#define REG_WR_FULL  (*(volatile uint32_t*)(LCPU_BASE + 0x6100 * 4))
#define REG_WR_WEN   (*(volatile uint32_t*)(LCPU_BASE + 0x6101 * 4))
#define REG_WR_ADDR  (*(volatile uint32_t*)(LCPU_BASE + 0x6102 * 4))
#define REG_WR_DATA  (*(volatile uint32_t*)(LCPU_BASE + 0x6103 * 4))
#define REG_WR_LEN   (*(volatile uint32_t*)(LCPU_BASE + 0x6104 * 4))
#define REG_WR_PUSH  (*(volatile uint32_t*)(LCPU_BASE + 0x6106 * 4))

// ── MDIO registers (sub-bus at 0x1000) ────────────────────────────────
#define MDIO_OPCODE  (*(volatile uint32_t*)(LCPU_BASE + 0x1000 * 4))
#define MDIO_PHYADDR (*(volatile uint32_t*)(LCPU_BASE + 0x1001 * 4))
#define MDIO_REGADDR (*(volatile uint32_t*)(LCPU_BASE + 0x1002 * 4))
#define MDIO_WRDATA  (*(volatile uint32_t*)(LCPU_BASE + 0x1003 * 4))
#define MDIO_OPDONE  (*(volatile uint32_t*)(LCPU_BASE + 0x100A * 4))
#define MDIO_RDDATA  (*(volatile uint32_t*)(LCPU_BASE + 0x100B * 4))
#define MDIO_OPSTART (*(volatile uint32_t*)(LCPU_BASE + 0x1014 * 4))
#define MDIO_OP_READ  2
#define MDIO_OP_WRITE 1

// ── Protocol offsets ──────────────────────────────────────────────────
#define ETH_HDR_LEN 14
#define IP_HDR_LEN  20

// ── Globals ───────────────────────────────────────────────────────────
static uint8_t  pkt_buf[PKT_BUF_SIZE];
static uint16_t pkt_len;
static uint32_t tcp_seq, tcp_ack;
static uint8_t  tcp_state;

// ── Mini printf (no stdlib dependency) ─────────────────────────────────
static int mini_sprintf(char *buf, const char *fmt, int v1, int v2) {
    char *p = buf;
    while (*fmt) {
        if (*fmt != '%') { *p++ = *fmt++; continue; }
        fmt++;
        int v = (*fmt == '1') ? v1 : v2;
        fmt++;
        char tmp[12]; int i = 0;
        if (v < 0) { *p++ = '-'; v = -v; }
        do { tmp[i++] = '0' + (v % 10); v /= 10; } while (v);
        while (i) *p++ = tmp[--i];
    }
    *p = 0;
    return p - buf;
}
static int mini_strcpy(char *dst, const char *src) {
    char *p = dst; while (*src) *p++ = *src++; *p = 0; return p - dst;
}

// ── Buffer helpers ────────────────────────────────────────────────────
static uint16_t r16(int off) { return (pkt_buf[off]<<8)|pkt_buf[off+1]; }
static void w16(int off, uint16_t v) { pkt_buf[off]=v>>8; pkt_buf[off+1]=v&0xFF; }

// ── Checksum ──────────────────────────────────────────────────────────
static uint16_t chksum(int off, int len) {
    uint32_t sum = 0;
    for (int i = 0; i < len; i++)
        sum += (uint16_t)(pkt_buf[off+i] << ((i&1)?0:8));
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return ~((uint16_t)sum);
}

// ── MDIO ──────────────────────────────────────────────────────────────
static uint16_t mdio_read(uint8_t pa, uint8_t ra) {
    MDIO_OPCODE=MDIO_OP_READ; MDIO_PHYADDR=pa; MDIO_REGADDR=ra; MDIO_OPSTART=1;
    while(!(MDIO_OPDONE&1)){}
    return MDIO_RDDATA & 0xFFFF;
}
static void mdio_write(uint8_t pa, uint8_t ra, uint16_t d) {
    MDIO_OPCODE=MDIO_OP_WRITE; MDIO_PHYADDR=pa; MDIO_REGADDR=ra;
    MDIO_WRDATA=d; MDIO_OPSTART=1;
    while(!(MDIO_OPDONE&1)){}
}

// ── Ethernet RX/TX ────────────────────────────────────────────────────
static int eth_rx(void) {
    if (REG_RD_EMPTY != 0) return 0;
    pkt_len = REG_RD_LEN & 0xFFFF;
    if (pkt_len < 60 || pkt_len > PKT_BUF_SIZE) { REG_RD_POP = 1; return 0; }
    for (uint16_t i = 0; i < pkt_len; i++) {
        REG_RD_ADDR = i; REG_RD_REN = 1; (void)REG_RD_DATA;
        pkt_buf[i] = REG_RD_DATA & 0xFF;
    }
    REG_RD_POP = 1;
    return pkt_len;
}
static void eth_tx(uint16_t len) {
    while (REG_WR_FULL != 0) {}
    for (uint16_t i = 0; i < len; i++) {
        REG_WR_ADDR = i; REG_WR_DATA = pkt_buf[i]; REG_WR_WEN = 1;
    }
    REG_WR_LEN = len; REG_WR_PUSH = 1;
}
static void makereply(uint16_t etype) {
    uint8_t tmp[6];
    for(int i=0;i<6;i++){tmp[i]=pkt_buf[i]; pkt_buf[i]=pkt_buf[i+6]; pkt_buf[i+6]=tmp[i];}
    w16(12, etype);
}
static void makeraw(const uint8_t *dst, uint16_t etype) {
    for(int i=0;i<6;i++) pkt_buf[i]=dst[i];
    pkt_buf[6]=MY_MAC0; pkt_buf[7]=MY_MAC1; pkt_buf[8]=MY_MAC2;
    pkt_buf[9]=MY_MAC3; pkt_buf[10]=MY_MAC4; pkt_buf[11]=MY_MAC5;
    w16(12, etype);
}

// ── ARP ───────────────────────────────────────────────────────────────
static int handle_arp(void) {
    int off = ETH_HDR_LEN;
    if (r16(off+6) != 1) return 0;
    if (pkt_buf[off+24]!=MY_IP0||pkt_buf[off+25]!=MY_IP1||
        pkt_buf[off+26]!=MY_IP2||pkt_buf[off+27]!=MY_IP3) return 0;
    uint8_t req_mac[6];
    for(int i=0;i<6;i++) req_mac[i]=pkt_buf[off+8+i];
    makeraw(req_mac, ETHERTYPE_ARP);
    int a = ETH_HDR_LEN;
    w16(a+0,0x0001); w16(a+2,0x0800); pkt_buf[a+4]=6; pkt_buf[a+5]=4; w16(a+6,0x0002);
    pkt_buf[a+8]=MY_MAC0; pkt_buf[a+9]=MY_MAC1; pkt_buf[a+10]=MY_MAC2;
    pkt_buf[a+11]=MY_MAC3; pkt_buf[a+12]=MY_MAC4; pkt_buf[a+13]=MY_MAC5;
    pkt_buf[a+14]=MY_IP0; pkt_buf[a+15]=MY_IP1; pkt_buf[a+16]=MY_IP2; pkt_buf[a+17]=MY_IP3;
    for(int i=0;i<6;i++) pkt_buf[a+18+i]=req_mac[i];
    pkt_buf[a+24]=pkt_buf[off+14]; pkt_buf[a+25]=pkt_buf[off+15];
    pkt_buf[a+26]=pkt_buf[off+16]; pkt_buf[a+27]=pkt_buf[off+17];
    eth_tx(ETH_HDR_LEN+28);
    return 1;
}

// ── TCP send ──────────────────────────────────────────────────────────
static void tcp_send(int sport, int dport, uint8_t flags, int data_off, int data_len) {
    int tcp_off = ETH_HDR_LEN + IP_HDR_LEN;
    int total   = IP_HDR_LEN + 20 + data_len;
    // TCP header
    w16(tcp_off, sport); w16(tcp_off+2, dport);
    pkt_buf[tcp_off+4]=tcp_seq>>24; pkt_buf[tcp_off+5]=(tcp_seq>>16)&0xFF;
    pkt_buf[tcp_off+6]=(tcp_seq>>8)&0xFF; pkt_buf[tcp_off+7]=tcp_seq&0xFF;
    pkt_buf[tcp_off+8]=tcp_ack>>24; pkt_buf[tcp_off+9]=(tcp_ack>>16)&0xFF;
    pkt_buf[tcp_off+10]=(tcp_ack>>8)&0xFF; pkt_buf[tcp_off+11]=tcp_ack&0xFF;
    pkt_buf[tcp_off+12]=0x50; pkt_buf[tcp_off+13]=flags; w16(tcp_off+14,0xB000);
    w16(tcp_off+16,0); w16(tcp_off+18,0);
    if (data_len>0)
        for(int i=0;i<data_len;i++) pkt_buf[tcp_off+20+i]=pkt_buf[data_off+i];
    // TCP checksum
    w16(tcp_off+16,0);
    uint32_t sum = (MY_IP0<<8|MY_IP1)+(MY_IP2<<8|MY_IP3);
    uint16_t dip = r16(ETH_HDR_LEN+16), dip2=r16(ETH_HDR_LEN+18);
    sum += dip + dip2 + 6 + 20 + data_len;
    for(int i=0;i<20+data_len;i++) sum += (uint16_t)(pkt_buf[tcp_off+i]<<((i&1)?0:8));
    while(sum>>16) sum=(sum&0xFFFF)+(sum>>16);
    w16(tcp_off+16, ~((uint16_t)sum));
    // IP header
    int ip = ETH_HDR_LEN;
    pkt_buf[ip]=0x45; pkt_buf[ip+1]=0x00; w16(ip+2,total); w16(ip+4,0x0001);
    pkt_buf[ip+6]=0; pkt_buf[ip+7]=0; pkt_buf[ip+8]=64; pkt_buf[ip+9]=IPPROTO_TCP;
    w16(ip+10,0); pkt_buf[ip+12]=MY_IP0; pkt_buf[ip+13]=MY_IP1;
    pkt_buf[ip+14]=MY_IP2; pkt_buf[ip+15]=MY_IP3;
    pkt_buf[ip+16]=(dip>>8)&0xFF; pkt_buf[ip+17]=dip&0xFF;
    pkt_buf[ip+18]=(dip2>>8)&0xFF; pkt_buf[ip+19]=dip2&0xFF;
    w16(ip+10, chksum(ip,20));
    eth_tx(ETH_HDR_LEN+total);
    if(flags&0x02) tcp_seq++;
    if(flags&0x10) tcp_seq+=data_len;
}

// ── HTTP response ─────────────────────────────────────────────────────
static int http_response(void) {
    int led = LCPU_REGS->my_reg.led_0 & 0xF;
    int pkts = LCPU_REGS->my_reg.scratch[10];
    static char page[512];
    int len = 0;
    len += mini_strcpy(page+len, "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
        "<!DOCTYPE html><html><head><title>RiscV WebSoC</title></head>"
        "<body><h2>RiscV WebSoC v1.0</h2>");
    len += mini_sprintf(page+len, "<p>LED state: 0x%1</p>", led, 0);
    len += mini_sprintf(page+len, "<p>Packets: %1</p>", pkts, 0);
    len += mini_strcpy(page+len, "</body></html>");
    int out_off = ETH_HDR_LEN + IP_HDR_LEN + 20;
    for (int i=0;i<len;i++) pkt_buf[out_off+i] = page[i];
    return len;
}

// ── TCP handler ───────────────────────────────────────────────────────
static int handle_tcp(int tcp_off, int ip_off) {
    uint16_t sport = r16(tcp_off), dport = r16(tcp_off+2);
    uint32_t seq = ((uint32_t)pkt_buf[tcp_off+4]<<24)|((uint32_t)pkt_buf[tcp_off+5]<<16)|
                   ((uint32_t)pkt_buf[tcp_off+6]<<8) |pkt_buf[tcp_off+7];
    uint8_t fl = pkt_buf[tcp_off+13];
    uint8_t doff = ((pkt_buf[tcp_off+12]>>4)&0xF)*4;
    int pl_off = tcp_off + doff, pl_len = pkt_len - pl_off;
    if (dport != 80) { makereply(ETHERTYPE_IPV4); tcp_send(dport,sport,0x04,0,0); return 1; }
    if (fl & 0x02) { tcp_seq=1000; tcp_ack=seq+1; tcp_state=TCP_SYN_RCVD;
        makereply(ETHERTYPE_IPV4); tcp_send(80,sport,0x12,0,0); return 1; }
    if ((fl&0x10)&&tcp_state==TCP_SYN_RCVD) { tcp_state=TCP_ESTABLISHED; tcp_seq++; tcp_ack=seq; return 0; }
    if ((fl&0x10)&&tcp_state==TCP_ESTABLISHED&&pl_len>0) { tcp_seq++; tcp_ack=seq+pl_len;
        makereply(ETHERTYPE_IPV4);
        int http_len = http_response();
        tcp_send(80,sport,0x18, ETH_HDR_LEN+IP_HDR_LEN+20, http_len); return 1; }
    if (fl&0x10) { tcp_seq++; tcp_ack=seq;
        makereply(ETHERTYPE_IPV4); tcp_send(80,sport,0x10,0,0); return 1; }
    return 0;
}

// ── IP handler ────────────────────────────────────────────────────────
static int handle_ip(void) {
    int ip_off = ETH_HDR_LEN;
    if ((pkt_buf[ip_off]>>4)!=4) return 0;
    uint8_t ihl = (pkt_buf[ip_off]&0x0F)*4;
    if (ihl<20) return 0;
    if (pkt_buf[ip_off+16]!=MY_IP0||pkt_buf[ip_off+17]!=MY_IP1||
        pkt_buf[ip_off+18]!=MY_IP2||pkt_buf[ip_off+19]!=MY_IP3) return 0;
    if (pkt_buf[ip_off+9]==IPPROTO_ICMP) {
        makereply(ETHERTYPE_IPV4);
        int ic=ETH_HDR_LEN+IP_HDR_LEN; pkt_buf[ic]=0x00; w16(ic+2,0);
        w16(ic+2, chksum(ic, pkt_len-ic)); eth_tx(pkt_len); return 1;
    }
    if (pkt_buf[ip_off+9]==IPPROTO_TCP) return handle_tcp(ip_off+ihl, ip_off);
    return 0;
}

// ── Public API ────────────────────────────────────────────────────────
void net_init(void) {
    mdio_write(PHY_ADDR, PHY_REG_BMCR, 0x8000);
    for(volatile int i=0;i<200000;i++){}
    uint16_t id1=mdio_read(PHY_ADDR, PHY_REG_PHYID1), id2=mdio_read(PHY_ADDR, PHY_REG_PHYID2);
    LCPU_REGS->my_reg.scratch[0]=id1; LCPU_REGS->my_reg.scratch[1]=id2;
    mdio_write(PHY_ADDR, PHY_REG_GBCR, 0x0200);
    mdio_write(PHY_ADDR, PHY_REG_ANAR, 0x01E0);
    mdio_write(PHY_ADDR, PHY_REG_BMCR, 0x1200);
    for(volatile int i=0;i<500000;i++){}
    tcp_state=TCP_CLOSED;
}

void net_poll(void) {
    if(!eth_rx()) return;
    uint16_t etype=r16(12);
    if(etype==ETHERTYPE_ARP) handle_arp();
    else if(etype==ETHERTYPE_IPV4) handle_ip();
}
