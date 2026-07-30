#include <stdint.h>
#ifndef NET_CONFIG_H
#define NET_CONFIG_H

// Static network configuration
#define MY_MAC0  0x00
#define MY_MAC1  0x0a
#define MY_MAC2  0x35
#define MY_MAC3  0x00
#define MY_MAC4  0x00
#define MY_MAC5  0x01

#define MY_IP0   192
#define MY_IP1   168
#define MY_IP2   1
#define MY_IP3   100

// PHY address (RTL8211F default)
#define PHY_ADDR 0x01

// RTL8211F key registers
#define PHY_REG_BMCR     0x00   // Basic Mode Control
#define PHY_REG_BMSR     0x01   // Basic Mode Status
#define PHY_REG_PHYID1   0x02   // PHY ID 1
#define PHY_REG_PHYID2   0x03   // PHY ID 2
#define PHY_REG_ANAR     0x04   // Auto-Negotiation Advertisement
#define PHY_REG_ANLPAR   0x05   // Auto-Negotiation Link Partner Ability
#define PHY_REG_GBCR     0x09   // 1000BASE-T Control

// Packet buffer size (must match cpu_channel parameter)
#define PKT_BUF_SIZE     2048

// Protocol numbers
#define ETHERTYPE_IPV4   0x0800
#define ETHERTYPE_ARP    0x0806
#define IPPROTO_ICMP     1
#define IPPROTO_TCP      6

// TCP states
#define TCP_CLOSED       0
#define TCP_LISTEN       1
#define TCP_SYN_RCVD     2
#define TCP_ESTABLISHED  3
#define TCP_FIN_WAIT     4

#endif
