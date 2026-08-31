`timescale 1ns / 1ps
`include "../../rtl/ip/gru/gru_defs.vh"

module gru_cmd_monitor (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        write_valid,
    input  logic [31:0] write_addr,
    input  logic [31:0] write_data,
    output logic        fb_base_write_valid,
    output logic [31:0] fb_base_write_data,
    output logic        depth_base_write_valid,
    output logic [31:0] depth_base_write_data,
    output logic        depth_ctrl_write_valid,
    output logic [31:0] depth_ctrl_write_data,
    output logic        cmd_valid,
    output logic [31:0] cmd_w0,
    output logic [31:0] cmd_w1,
    output logic        ext_cmd_valid,
    output logic [31:0] ext_cmd_w0,
    output logic [31:0] ext_cmd_w1,
    output logic [31:0] ext_cmd_w2,
    output logic [31:0] ext_cmd_w3,
    output logic [31:0] ext_cmd_w4,
    output logic [31:0] ext_cmd_cmd_w0,
    output logic [31:0] ext_cmd_cmd_w1
);

    logic [31:0] cmd_w0_shadow;
    logic [31:0] cmd_w1_shadow;
    logic [31:0] ext_w0_shadow;
    logic [31:0] ext_w1_shadow;
    logic [31:0] ext_w2_shadow;
    logic [31:0] ext_w3_shadow;
    logic [31:0] ext_w4_shadow;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            cmd_w0_shadow      <= 32'd0;
            cmd_w1_shadow      <= 32'd0;
            ext_w0_shadow      <= 32'd0;
            ext_w1_shadow      <= 32'd0;
            ext_w2_shadow      <= 32'd0;
            ext_w3_shadow      <= 32'd0;
            ext_w4_shadow      <= 32'd0;
            fb_base_write_valid <= 1'b0;
            fb_base_write_data <= 32'd0;
            depth_base_write_valid <= 1'b0;
            depth_base_write_data <= 32'd0;
            depth_ctrl_write_valid <= 1'b0;
            depth_ctrl_write_data <= 32'd0;
            cmd_valid          <= 1'b0;
            cmd_w0             <= 32'd0;
            cmd_w1             <= 32'd0;
            ext_cmd_valid      <= 1'b0;
            ext_cmd_w0         <= 32'd0;
            ext_cmd_w1         <= 32'd0;
            ext_cmd_w2         <= 32'd0;
            ext_cmd_w3         <= 32'd0;
            ext_cmd_w4         <= 32'd0;
            ext_cmd_cmd_w0     <= 32'd0;
            ext_cmd_cmd_w1     <= 32'd0;
        end else begin
            fb_base_write_valid <= 1'b0;
            depth_base_write_valid <= 1'b0;
            depth_ctrl_write_valid <= 1'b0;
            cmd_valid           <= 1'b0;
            ext_cmd_valid       <= 1'b0;

            if (write_valid) begin
                case (write_addr[7:0])
                    `GRU_REG_FB_BASE: begin
                        fb_base_write_valid <= 1'b1;
                        fb_base_write_data  <= write_data;
                    end
                    `GRU_REG_DEPTH_BASE: begin
                        depth_base_write_valid <= 1'b1;
                        depth_base_write_data  <= write_data;
                    end
                    `GRU_REG_DEPTH_CTRL: begin
                        depth_ctrl_write_valid <= 1'b1;
                        depth_ctrl_write_data  <= write_data;
                    end
                    `GRU_REG_CMD_W0: begin
                        cmd_w0_shadow <= write_data;
                    end
                    `GRU_REG_CMD_W1: begin
                        cmd_w1_shadow <= write_data;
                    end
                    `GRU_REG_EXT_W0: begin
                        ext_w0_shadow <= write_data;
                    end
                    `GRU_REG_EXT_W1: begin
                        ext_w1_shadow <= write_data;
                    end
                    `GRU_REG_EXT_W2: begin
                        ext_w2_shadow <= write_data;
                    end
                    `GRU_REG_EXT_W3: begin
                        ext_w3_shadow <= write_data;
                    end
                    `GRU_REG_EXT_W4: begin
                        ext_w4_shadow <= write_data;
                    end
                    `GRU_REG_CMD_PUSH: begin
                        if (write_data[0]) begin
                            cmd_valid <= 1'b1;
                            cmd_w0    <= cmd_w0_shadow;
                            cmd_w1    <= cmd_w1_shadow;
                        end
                    end
                    `GRU_REG_EXT_PUSH: begin
                        if (write_data[0]) begin
                            ext_cmd_valid  <= 1'b1;
                            ext_cmd_w0     <= ext_w0_shadow;
                            ext_cmd_w1     <= ext_w1_shadow;
                            ext_cmd_w2     <= ext_w2_shadow;
                            ext_cmd_w3     <= ext_w3_shadow;
                            ext_cmd_w4     <= ext_w4_shadow;
                            ext_cmd_cmd_w0 <= cmd_w0_shadow;
                            ext_cmd_cmd_w1 <= cmd_w1_shadow;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
