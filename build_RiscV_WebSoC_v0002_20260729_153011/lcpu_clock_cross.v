//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        lcpu_clock_cross	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-25 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    lcpu bus pass clock region
//                                                                            //
// Modification history:[including time, version, author and abstract]        //
// 2014-12-25 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                     //
// *********************************end************************************** //

module lcpu_clock_cross (
    reset_l,

    clk1,
    op_req_clk1,
    wrl_rdh_clk1,  //'0': write, '1': read
    wrdata_clk1,
    address_clk1,
    op_ack_clk1,
    rddata_clk1,

    clk2,
    op_req_clk2,
    wrl_rdh_clk2,  //'0': write, '1': read
    wrdata_clk2,
    address_clk2,
    op_ack_clk2,
    rddata_clk2
);

  parameter addr_width = 32, data_width = 32;

  parameter pass_clock_muticycle = 4;  //default 4 if satisfy timing

  input reset_l;

  input clk1;
  input op_req_clk1;
  input wrl_rdh_clk1;
  input [data_width-1:0] wrdata_clk1;
  input [addr_width-1:0] address_clk1;
  output op_ack_clk1;
  output [data_width-1:0] rddata_clk1;

  input clk2;
  output op_req_clk2;
  output wrl_rdh_clk2;
  output [data_width-1:0] wrdata_clk2;
  output [addr_width-1:0] address_clk2;
  input op_ack_clk2;
  input [data_width-1:0] rddata_clk2;


  wire                            op_req_clk2_s;
  reg  [pass_clock_muticycle-1:0] op_req_clk2_d;
  reg                             op_req_clk2;
  reg                             wrl_rdh_clk2;
  reg  [          data_width-1:0] wrdata_clk2;
  reg  [          addr_width-1:0] address_clk2;

  wire                            op_ack_clk1_s;
  reg  [pass_clock_muticycle-1:0] op_ack_clk1_d;
  reg                             wrl_rdh_clk1_r;
  reg                             op_ack_clk1;
  reg  [          data_width-1:0] rddata_clk1;


  always @(negedge reset_l or posedge clk2)
    if (reset_l == 1'b0) begin
      op_req_clk2_d <= {pass_clock_muticycle{1'b0}};
      op_req_clk2   <= 1'b0;
      wrl_rdh_clk2  <= 1'b1;
      wrdata_clk2   <= {data_width{1'b0}};
      address_clk2  <= {addr_width{1'b0}};
    end else begin
      op_req_clk2_d <= {op_req_clk2_d[pass_clock_muticycle-2:0], op_req_clk2_s};
      op_req_clk2   <= op_req_clk2_d[pass_clock_muticycle-1];
      wrl_rdh_clk2  <= wrl_rdh_clk1_r;
      wrdata_clk2   <= wrdata_clk1;
      address_clk2  <= address_clk1;
    end

  always @(negedge reset_l or posedge clk1)
    if (reset_l == 1'b0) begin
      op_ack_clk1_d <= {pass_clock_muticycle{1'b0}};
      op_ack_clk1 <= 1'b0;
      rddata_clk1 <= {data_width{1'b0}};
      wrl_rdh_clk1_r <= 1'b1;
    end else begin
      op_ack_clk1_d <= {op_ack_clk1_d[pass_clock_muticycle-2:0], op_ack_clk1_s};
      op_ack_clk1   <= op_ack_clk1_d[pass_clock_muticycle-1];
      rddata_clk1   <= rddata_clk2;
      if (op_req_clk1 == 1'b1) begin
        wrl_rdh_clk1_r <= wrl_rdh_clk1;
      end
    end
  pulse_clock_region_pass u_req_pulse_clock_region_pass (
      .reset_l(reset_l),
      .clk_a  (clk1),
      .pulse_a(op_req_clk1),
      .clk_b  (clk2),
      .pulse_b(op_req_clk2_s)
  );
  pulse_clock_region_pass u_ack_pulse_clock_region_pass (
      .reset_l(reset_l),
      .clk_a  (clk2),
      .pulse_a(op_ack_clk2),
      .clk_b  (clk1),
      .pulse_b(op_ack_clk1_s)
  );
endmodule  // lcpu_clock_cross

