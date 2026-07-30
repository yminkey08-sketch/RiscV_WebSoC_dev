//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        lcpu_mdio	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2015-01-06 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    lcpu as master, mdio as slave.
//                                                          //
// Modification history:[including time, version, author and abstract]        //
// 2015-01-06 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                     //
// *********************************end************************************** //

module lcpu_mdio (
    reset_l,
    clk,

    op_req,
    wrl_rdh,  //'0': write, '1': read
    wrdata,
    address,
    op_ack,
    rddata,

    mdc,
    mdio
);

  input reset_l;
  input clk;

  input op_req;
  input wrl_rdh;
  input [31:0] wrdata;
  input [31:0] address;
  output op_ack;
  output [31:0] rddata;

  output mdc;
  inout mdio;

  wire        mdio_clk;
  wire        op_req_clk2;
  wire        wrl_rdh_clk2;
  wire [31:0] wrdata_clk2;
  wire [31:0] address_clk2;
  wire        op_ack_clk2;
  wire [31:0] rddata_clk2;

  wire [ 1:0] mdio_opcode;
  wire [ 4:0] mdio_phyaddr;
  wire [ 4:0] mdio_regaddr;
  wire [15:0] mdio_wrdata;
  wire        mdio_opdone;
  wire [15:0] mdio_rddata;
  wire        mdio_opstart;


  clock_frequency_divider #(
      .div_Mbits(28),
      .div_Nbits(28)
  ) u_clock_frequency_divider (
      .reset_l(reset_l),
      .clk_in (clk),
      .div_M  (28'd50000000),  //input is 50M clock
      .div_N  (28'd2500000),   //output clock 2.5Mhz
      .clk_out(mdio_clk)
  );

  lcpu_clock_cross #(
      .addr_width(32),
      .data_width(32),
      .pass_clock_muticycle(4)
  ) u_lcpu_clock_cross (
      .reset_l     (reset_l),
      .clk1        (clk),
      .op_req_clk1 (op_req),
      .wrl_rdh_clk1(wrl_rdh),       //'0': write, '1': read
      .wrdata_clk1 (wrdata),
      .address_clk1(address),
      .op_ack_clk1 (op_ack),
      .rddata_clk1 (rddata),
      .clk2        (mdio_clk),
      .op_req_clk2 (op_req_clk2),
      .wrl_rdh_clk2(wrl_rdh_clk2),  //'0': write, '1': read
      .wrdata_clk2 (wrdata_clk2),
      .address_clk2(address_clk2),
      .op_ack_clk2 (op_ack_clk2),
      .rddata_clk2 (rddata_clk2)
  );

  lcpu_access_mdio_reg u_reg (
      .clk             (mdio_clk),
      .reset_l         (reset_l),
      .op_req          (op_req_clk2),
      .wrl_rdh         (wrl_rdh_clk2),
      .address         (address_clk2),
      .wrdata          (wrdata_clk2),
      .rddata          (rddata_clk2),
      .op_ack          (op_ack_clk2),
      .mdio_opcode     (mdio_opcode),
      .mdio_phyaddr    (mdio_phyaddr),
      .mdio_regaddr    (mdio_regaddr),
      .mdio_wrdata     (mdio_wrdata),
      .mdio_opdone     (mdio_opdone),
      .mdio_rddata     (mdio_rddata),
      .mdio_opstart    (),
      .mdio_opstart_ind(mdio_opstart)
  );


  mdio_ctrl u_mdio_ctrl (
      .reset_l (reset_l),
      .clk     (mdio_clk),
      .op_start(mdio_opstart),
      .opcode  (mdio_opcode),
      .phy_addr(mdio_phyaddr),
      .reg_addr(mdio_regaddr),
      .wrdata  (mdio_wrdata),
      .op_done (mdio_opdone),
      .rddata  (mdio_rddata),
      .mdc     (mdc),
      .mdio    (mdio)
  );
endmodule  // lcpu_mdio


//****************************************Copyright 2014[c]************************//
// ************************Declaration***************************************//
// File name:        lcpu_access_mdio_reg.v
// Author:           huaming.huang@link-real.com.cn                             //
// Date:             2015/1/6 13:34:13                                      //
// Version Number:   1.1                                                     //
// Abstract:auto generate top cpu access fpga registers                      //
//                                                                           //
// Modification history:[including time, version, author and abstract]       //
// 2015/1/6 13:34:13        version 1.1     xxx                             //
// Abstract: Initial                                                         //
//                                                                           //
// *********************************end**************************************//

module lcpu_access_mdio_reg (
    input             clk,
    input             reset_l,
    input             op_req,
    input             wrl_rdh,          //'0': write, '1': read
    input      [31:0] address,
    input      [31:0] wrdata,
    output reg [31:0] rddata,
    output reg        op_ack,
    output reg [ 1:0] mdio_opcode,
    output reg [ 4:0] mdio_phyaddr,
    output reg [ 4:0] mdio_regaddr,
    output reg [15:0] mdio_wrdata,
    input             mdio_opdone,
    input      [15:0] mdio_rddata,
    output reg        mdio_opstart,
    output reg        mdio_opstart_ind
);

  reg op_req_d0;


  always @(posedge clk or negedge reset_l) begin
    if (reset_l == 1'b0) begin
      mdio_opcode  <= 0;
      mdio_phyaddr <= 0;
      mdio_regaddr <= 0;
      mdio_wrdata  <= 0;
    end else begin
      if (op_req == 1'b1) begin
        if (wrl_rdh == 1'b0) begin
          if (address == 0) begin
            mdio_opcode <= wrdata;
          end
          if (address == 1) begin
            mdio_phyaddr <= wrdata;
          end
          if (address == 2) begin
            mdio_regaddr <= wrdata;
          end
          if (address == 3) begin
            mdio_wrdata <= wrdata;
          end
        end
      end
    end
  end
  always @(posedge clk or negedge reset_l) begin
    if (reset_l == 1'b0) begin
      mdio_opstart <= 0;
      mdio_opstart_ind <= 0;
    end else begin

      mdio_opstart_ind <= 1'b0;
      if (op_req == 1'b1) begin
        if (wrl_rdh == 1'b0) begin

          if (address == 20) begin
            mdio_opstart <= wrdata;
            mdio_opstart_ind <= 1'b1;
          end
        end
      end
    end
  end
  always @(posedge clk or negedge reset_l) begin
    if (reset_l == 1'b0) begin
      rddata <= 0;
    end else begin
      if (op_req == 1'b1) begin
        if (wrl_rdh == 1'b1) begin
          if (address == 0) begin
            rddata <= mdio_opcode;
          end
          if (address == 1) begin
            rddata <= mdio_phyaddr;
          end
          if (address == 2) begin
            rddata <= mdio_regaddr;
          end
          if (address == 3) begin
            rddata <= mdio_wrdata;
          end
          if (address == 10) begin
            rddata <= mdio_opdone;
          end
          if (address == 11) begin
            rddata <= mdio_rddata;
          end
        end
      end
    end
  end
  always @(posedge clk or negedge reset_l) begin
    if (reset_l == 1'b0) begin
      op_req_d0 <= 0;
      op_ack <= 0;
    end else begin
      op_req_d0 <= op_req;
      op_ack <= op_req_d0;
    end
  end
endmodule


