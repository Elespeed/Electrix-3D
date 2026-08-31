module sketch_cmd_monitor(
    input logic clk,input logic resetn,input logic valid,input logic we,input logic ready,
    input logic [31:0] addr,input logic [31:0] wdata,output logic error,
    output logic [31:0] clear_count,output logic [31:0] fill_count,output logic [31:0] tri_count,output logic [31:0] present_count
);
    logic [4:0] opcode_shadow; logic seen_clear;
    always_ff @(posedge clk or negedge resetn) begin
      if(!resetn) begin error<=0;clear_count<=0;fill_count<=0;tri_count<=0;present_count<=0;opcode_shadow<=0;seen_clear<=0;end
      else if(valid&&we&&ready) begin
        if(addr[11:0]==12'h008) opcode_shadow<=wdata[4:0];
        if(addr[11:0]==12'h018) begin
          case(opcode_shadow)
            0: begin clear_count<=clear_count+1;seen_clear<=1;end
            1: begin fill_count<=fill_count+1;seen_clear<=1;end
            5: begin tri_count<=tri_count+1;if(!seen_clear) error<=1;end
            6: begin present_count<=present_count+1;if(!seen_clear) error<=1;seen_clear<=0;end
            default: error<=1;
          endcase
        end
      end
    end
endmodule
