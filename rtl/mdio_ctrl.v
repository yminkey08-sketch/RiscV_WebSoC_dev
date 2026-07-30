//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        mdio_ctrl	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2015-01-06 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:         mdio master
//                                                                            //
// Modification history:[including time, version, author and abstract]        //
// 2015-01-06 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                     //
// *********************************end************************************** //

module mdio_ctrl (
    reset_l,
    clk,  // 2.5Mhz ~ 25Mhz

    op_start,
    opcode,
    phy_addr,
    reg_addr,
    wrdata,
    op_done,
    rddata,

    mdc,
    mdio
);


  parameter [2:0] idle = 3'b001, mdio_write = 3'b010, mdio_read = 3'b100;

  input reset_l;
  input clk;

  input op_start;
  input [1:0] opcode;
  input [4:0] phy_addr;
  input [4:0] reg_addr;
  input [15:0] wrdata;
  output op_done;
  output [15:0] rddata;

  output mdc;
  inout mdio;


  reg         wr_mdio_done;
  reg         rd_mdio_done;
  reg  [ 7:0] op_mdio_cnt;

  wire        mdio_data_in;
  reg         mdio_data_out;
  reg         mdio_out_en;
  reg         op_done;
  reg  [15:0] rddata;

  reg  [ 2:0] cur_state;
  reg  [ 2:0] next_state;
  assign mdc = clk;
  assign mdio = (mdio_out_en == 1'b1) ? mdio_data_out : 1'bz;
  assign mdio_data_in = mdio;

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      cur_state <= idle;
    end else begin
      cur_state <= next_state;
    end
  end

  always_comb begin
    case (cur_state)
      idle: begin
        if (op_start == 1'b1) begin
          if (opcode == 2'b10) begin
            next_state = mdio_read;
          end else if (opcode == 2'b01) begin
            next_state = mdio_write;
          end else begin
            next_state = idle;
          end
        end else begin
          next_state = idle;
        end
      end
      mdio_write: begin
        if (wr_mdio_done == 1'b1) begin
          next_state = idle;
        end else begin
          next_state = mdio_write;
        end
      end
      mdio_read: begin
        if (rd_mdio_done == 1'b1) begin
          next_state = idle;
        end else begin
          next_state = mdio_read;
        end
      end
      default: next_state = idle;
    endcase
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      op_mdio_cnt <= 8'b0;
    end else begin
      if (cur_state != idle) begin
        op_mdio_cnt <= op_mdio_cnt + 1;
      end else begin
        op_mdio_cnt <= 8'b0;
      end
    end
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      wr_mdio_done <= 1'b0;
      rd_mdio_done <= 1'b0;
      mdio_out_en <= 1'b1;
      mdio_data_out <= 1'b1;
      rddata <= 16'b0;
    end else begin
      wr_mdio_done  <= 1'b0;
      rd_mdio_done  <= 1'b0;
      mdio_out_en   <= 1'b0;
      mdio_data_out <= 1'b1;
      case (cur_state)
        mdio_read: begin
          case (op_mdio_cnt)
            32 + 0: begin  //>=32
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b0;
            end
            32 + 1: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b1;
            end
            32 + 2: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b1;
            end
            32 + 3: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b0;
            end
            32 + 4: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[4];
            end
            32 + 5: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[3];
            end
            32 + 6: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[2];
            end
            32 + 7: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[1];
            end
            32 + 8: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[0];
            end
            32 + 9: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[4];
            end
            32 + 10: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[3];
            end
            32 + 11: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[2];
            end
            32 + 12: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[1];
            end
            32 + 13: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[0];
            end
            32 + 17: rddata[15] <= mdio_data_in;
            32 + 18: rddata[14] <= mdio_data_in;
            32 + 19: rddata[13] <= mdio_data_in;
            32 + 20: rddata[12] <= mdio_data_in;
            32 + 21: rddata[11] <= mdio_data_in;
            32 + 22: rddata[10] <= mdio_data_in;
            32 + 23: rddata[9] <= mdio_data_in;
            32 + 24: rddata[8] <= mdio_data_in;
            32 + 25: rddata[7] <= mdio_data_in;
            32 + 26: rddata[6] <= mdio_data_in;
            32 + 27: rddata[5] <= mdio_data_in;
            32 + 28: rddata[4] <= mdio_data_in;
            32 + 29: rddata[3] <= mdio_data_in;
            32 + 30: rddata[2] <= mdio_data_in;
            32 + 31: rddata[1] <= mdio_data_in;
            32 + 32: rddata[0] <= mdio_data_in;
            32 + 33: rd_mdio_done <= 1'b1;
            default: begin
              mdio_out_en   <= 1'b0;
              mdio_data_out <= 1'b0;
              rd_mdio_done  <= 1'b0;
              wr_mdio_done  <= 1'b0;
            end
          endcase
          if (op_mdio_cnt < 32) begin  //0~31
            mdio_out_en   <= 1'b1;
            mdio_data_out <= 1'b1;
          end
        end
        mdio_write: begin
          case (op_mdio_cnt)
            32 + 0: begin  //>=32
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b0;
            end
            32 + 1: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b1;
            end
            32 + 2: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b0;
            end
            32 + 3: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b1;
            end
            32 + 4: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[4];
            end
            32 + 5: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[3];
            end
            32 + 6: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[2];
            end
            32 + 7: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[1];
            end
            32 + 8: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= phy_addr[0];
            end
            32 + 9: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[4];
            end
            32 + 10: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[3];
            end
            32 + 11: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[2];
            end
            32 + 12: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[1];
            end
            32 + 13: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= reg_addr[0];
            end
            32 + 14: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b1;
            end
            32 + 15: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= 1'b0;
            end
            32 + 16: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[15];
            end
            32 + 17: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[14];
            end
            32 + 18: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[13];
            end
            32 + 19: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[12];
            end
            32 + 20: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[11];
            end
            32 + 21: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[10];
            end
            32 + 22: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[9];
            end
            32 + 23: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[8];
            end
            32 + 24: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[7];
            end
            32 + 25: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[6];
            end
            32 + 26: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[5];
            end
            32 + 27: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[4];
            end
            32 + 28: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[3];
            end
            32 + 29: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[2];
            end
            32 + 30: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[1];
            end
            32 + 31: begin
              mdio_out_en   <= 1'b1;
              mdio_data_out <= wrdata[0];
            end
            32 + 32: wr_mdio_done <= 1'b1;
            default: begin
              mdio_out_en   <= 1'b0;
              mdio_data_out <= 1'b0;
              rd_mdio_done  <= 1'b0;
              wr_mdio_done  <= 1'b0;
            end
          endcase
          if (op_mdio_cnt < 32) begin  //0~31
            mdio_out_en   <= 1'b1;
            mdio_data_out <= 1'b1;
          end
        end
        default: begin
          mdio_out_en   <= 1'b1;
          mdio_data_out <= 1'b1;
          rd_mdio_done  <= 1'b0;
          wr_mdio_done  <= 1'b0;
        end
      endcase
    end
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      op_done <= 1'b1;
    end else begin
      if (op_start == 1'b1) begin
        op_done <= 1'b0;
      end
      if (rd_mdio_done == 1'b1 || wr_mdio_done == 1'b1) begin
        op_done <= 1'b1;
      end
    end
  end
endmodule  // mdio_ctrl
