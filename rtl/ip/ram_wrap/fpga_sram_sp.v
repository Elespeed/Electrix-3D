module fpga_sram_sp #(
    parameter AW = 16,
    parameter DATA_WIDTH = 32,
    parameter Init_File = "none"
)
(
    input  wire          CLK,
    input  wire [AW-1:0] ADDR,
    input  wire [DATA_WIDTH-1:0]   WDATA,
    input  wire [DATA_WIDTH/8-1:0] WREN,
    input  wire          CS,
    output wire [DATA_WIDTH-1:0]   RDATA
);

    localparam AWT = ((1<<(AW-0))-1);
    localparam V_STYLE = "block";
    localparam P_STYLE =    (V_STYLE == "ultra")        ? "uram" :
                            (V_STYLE == "distributed")  ? "select_ram" :
                            "block_ram";

    (*ram_style = V_STYLE*)reg [DATA_WIDTH-1:0] BRAM [AWT:0]/*synthesis syn_ramstyle=P_STYLE*/;

    initial begin
        if(Init_File != "none") begin
            $readmemb(Init_File,BRAM);
        end
    end
    
    reg     [AW-1:0]  addr_q1;
    wire    [DATA_WIDTH/8-1:0] write_enable;

    assign write_enable = WREN & {DATA_WIDTH/8{CS}};

    genvar byte_idx;
    generate
        for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx = byte_idx + 1) begin : gen_byte_write
            always @(posedge CLK) begin
                if (write_enable[byte_idx]) begin
                    BRAM[ADDR][(byte_idx*8) +: 8] <= WDATA[(byte_idx*8) +: 8];
                end
            end
        end
    endgenerate

    always @ (posedge CLK) begin
        if(CS && !(|WREN))
            addr_q1 <= ADDR[AW-1:0];
    end

    assign RDATA  = BRAM[addr_q1];

endmodule
