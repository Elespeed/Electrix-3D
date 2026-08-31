// Scene-controller register bank.  The interface is deliberately the same
// single-beat AXI subset used by sketch_book_axi, so it can later be placed
// behind the SoC crossbar without an adapter.
module scene_ctrl_axi_regs (
    input logic clk, input logic resetn,
    input logic s_awvalid, output logic s_awready, input logic [31:0] s_awaddr,
    input logic [4:0] s_awid, input logic [7:0] s_awlen, input logic [2:0] s_awsize,
    input logic [1:0] s_awburst, input logic s_awlock, input logic [3:0] s_awcache, input logic [2:0] s_awprot,
    input logic s_wvalid, output logic s_wready, input logic [31:0] s_wdata, input logic [3:0] s_wstrb, input logic s_wlast,
    output logic s_bvalid, input logic s_bready, output logic [4:0] s_bid, output logic [1:0] s_bresp,
    input logic s_arvalid, output logic s_arready, input logic [31:0] s_araddr, input logic [4:0] s_arid,
    input logic [7:0] s_arlen, input logic [2:0] s_arsize, input logic [1:0] s_arburst, input logic s_arlock,
    input logic [3:0] s_arcache, input logic [2:0] s_arprot, output logic s_rvalid, input logic s_rready,
    output logic [31:0] s_rdata, output logic [4:0] s_rid, output logic [1:0] s_rresp, output logic s_rlast,
    output logic load_start, output logic render_start, output logic abort, output logic soft_reset,
    output logic [31:0] model_base, output logic [31:0] model_size,
    output logic [15:0] yaw, output logic [15:0] pitch, output logic [15:0] roll, output logic [15:0] scale,
    output logic [15:0] center_x, output logic [15:0] center_y, output logic [15:0] translate_z,
    output logic [5:0] render_cfg, output logic [7:0] clear_color,
    output logic [15:0] viewport_x, output logic [15:0] viewport_y,
    output logic [15:0] viewport_w, output logic [15:0] viewport_h,
    output logic [1:0] viewport_cfg,
    output logic cmd_mode, output logic cmd_push, output logic [127:0] cmd_data, output logic cmd_frame_start,
    input logic busy, input logic load_done, input logic render_done, input logic error, input logic gru_backpressure,
    input logic model_valid, input logic [7:0] error_code, input logic [15:0] vertex_count, input logic [15:0] triangle_count,
    input logic cmd_ready, input logic [4:0] cmd_level, input logic cmd_full, input logic cmd_locked, input logic [31:0] cmd_frame_count, input logic [3:0] cmd_mesh_count
);
    logic wr_have, wr_bad; logic [31:0] wr_addr; logic [4:0] wr_id;
    wire bad_aw = (s_awlen != 0) || (s_awsize != 3'd2) || (s_awburst != 2'b01);
    wire bad_ar = (s_arlen != 0) || (s_arsize != 3'd2) || (s_arburst != 2'b01);
    assign s_awready = !wr_have && !s_bvalid && !s_rvalid;
    assign s_wready = wr_have && !s_bvalid;
    assign s_arready = !wr_have && !s_bvalid && !s_rvalid;
    assign s_bid = wr_id; assign s_rid = s_arid; assign s_rlast = 1'b1;
    always_ff @(posedge clk or negedge resetn) begin
      if (!resetn) begin
        wr_have<=0; wr_bad<=0; wr_addr<=0; wr_id<=0; s_bvalid<=0; s_bresp<=0; s_rvalid<=0; s_rresp<=0; s_rdata<=0;
        load_start<=0; render_start<=0; abort<=0; soft_reset<=0; cmd_push<=0; cmd_frame_start<=0; cmd_mode<=0; cmd_data<=0;
        model_base<=32'h0040_0000; model_size<=0; yaw<=0; pitch<=0; roll<=0; scale<=16'h0100;
        center_x<=16'd200; center_y<=16'd150; translate_z<=0; render_cfg<=6'b001111; clear_color<=8'h18;
        viewport_x<=0; viewport_y<=0; viewport_w<=16'd400; viewport_h<=16'd300; viewport_cfg<=0;
      end else begin
        load_start<=0; render_start<=0; abort<=0; soft_reset<=0; cmd_push<=0; cmd_frame_start<=0;
        if(s_awvalid && s_awready) begin wr_have<=1; wr_bad<=bad_aw; wr_addr<=s_awaddr; wr_id<=s_awid; end
        if(wr_have && s_wvalid && s_wready) begin
          wr_have<=0; s_bvalid<=1; s_bresp <= (wr_bad || !s_wlast || s_wstrb!=4'hf) ? 2'b10 : 2'b00;
          if(!wr_bad && s_wlast && s_wstrb==4'hf) case(wr_addr[11:0])
            12'h000: begin load_start<=s_wdata[1] && !busy; render_start<=s_wdata[2] && !busy && model_valid; abort<=s_wdata[3]; soft_reset<=s_wdata[4]; end
            12'h008: model_base<=s_wdata; 12'h00c: model_size<=s_wdata;
            12'h014: begin yaw<=s_wdata[15:0]; pitch<=s_wdata[31:16]; end
            12'h018: begin roll<=s_wdata[15:0]; scale<=s_wdata[31:16]; end
            12'h01c: begin center_x<=s_wdata[15:0]; center_y<=s_wdata[31:16]; end
            12'h020: translate_z<=s_wdata[15:0]; 12'h024: render_cfg<=s_wdata[5:0]; 12'h028: clear_color<=s_wdata[7:0];
            12'h02c: begin viewport_x<=s_wdata[15:0]; viewport_y<=s_wdata[31:16]; end
            12'h030: begin viewport_w<=s_wdata[15:0]; viewport_h<=s_wdata[31:16]; end
            12'h034: viewport_cfg<=s_wdata[1:0];
            12'h038: if (!busy) cmd_mode<=s_wdata[0];
            12'h03c: cmd_data[31:0]<=s_wdata;
            12'h040: cmd_data[63:32]<=s_wdata;
            12'h044: cmd_data[95:64]<=s_wdata;
            12'h048: cmd_data[127:96]<=s_wdata;
            12'h04c: cmd_push<=s_wdata[0] && cmd_mode && cmd_ready;
            12'h050: cmd_frame_start<=s_wdata[0] && cmd_mode && !cmd_locked && (cmd_level != 0);
            default: ; endcase
        end
        if(s_bvalid && s_bready) s_bvalid<=0;
        if(s_arvalid && s_arready) begin
          s_rvalid<=1; s_rresp<=bad_ar ? 2'b10 : 2'b00;
          case(s_araddr[11:0])
            12'h004: s_rdata<={16'd0,error_code,2'd0,model_valid,gru_backpressure,error,render_done,load_done,busy};
            12'h008: s_rdata<=model_base; 12'h00c: s_rdata<=model_size; 12'h010: s_rdata<={triangle_count,vertex_count};
            12'h014: s_rdata<={pitch,yaw}; 12'h018:s_rdata<={scale,roll}; 12'h01c:s_rdata<={center_y,center_x};
            12'h020:s_rdata<={16'd0,translate_z}; 12'h024:s_rdata<={26'd0,render_cfg}; 12'h028:s_rdata<={24'd0,clear_color};
            12'h02c:s_rdata<={viewport_y,viewport_x}; 12'h030:s_rdata<={viewport_h,viewport_w}; 12'h034:s_rdata<={30'd0,viewport_cfg};
            12'h038:s_rdata<={31'd0,cmd_mode};
            12'h03c:s_rdata<=cmd_data[31:0]; 12'h040:s_rdata<=cmd_data[63:32]; 12'h044:s_rdata<=cmd_data[95:64]; 12'h048:s_rdata<=cmd_data[127:96];
            12'h054:s_rdata<={cmd_frame_count[15:0],cmd_mesh_count,cmd_level,4'd0,cmd_locked,cmd_full,cmd_ready};
            default:s_rdata<=0; endcase
        end
        if(s_rvalid && s_rready) s_rvalid<=0;
      end
    end
endmodule
