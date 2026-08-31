module digitaltube_board_controller(
    input  wire [31:0] control_reg,
    input  wire [31:0] data_reg,
    input  wire        clk,
    input  wire        rst_n,
    output reg  [7:0]  seg_data,
    output reg  [7:0]  seg_an
);

    reg [6:0] seg_code [0:15];
    reg [2:0] scan_idx;
    reg [15:0] scan_div;
    reg [7:0] digit_data [0:7];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_code[0]  <= 7'b1000000;
            seg_code[1]  <= 7'b1111001;
            seg_code[2]  <= 7'b0100100;
            seg_code[3]  <= 7'b0110000;
            seg_code[4]  <= 7'b0011001;
            seg_code[5]  <= 7'b0010010;
            seg_code[6]  <= 7'b0000010;
            seg_code[7]  <= 7'b1111000;
            seg_code[8]  <= 7'b0000000;
            seg_code[9]  <= 7'b0010000;
            seg_code[10] <= 7'b0001000;
            seg_code[11] <= 7'b0000011;
            seg_code[12] <= 7'b1000110;
            seg_code[13] <= 7'b0100001;
            seg_code[14] <= 7'b0000110;
            seg_code[15] <= 7'b0001110;
        end
    end

    always @(*) begin
        for (i = 0; i < 8; i = i + 1) begin
            digit_data[i] = 8'hff;
        end

        if (control_reg[1:0] == 2'b01) begin
            digit_data[0] = {seg_code[data_reg[3:0]], 1'b1};
        end
        else if (control_reg[1:0] == 2'b10) begin
            digit_data[0] = {seg_code[data_reg[3:0]], 1'b0};
        end

        if (control_reg[3:2] == 2'b01) begin
            digit_data[1] = {seg_code[data_reg[7:4]], 1'b1};
        end
        else if (control_reg[3:2] == 2'b10) begin
            digit_data[1] = {seg_code[data_reg[7:4]], 1'b0};
        end

        if (control_reg[5:4] == 2'b01) begin
            digit_data[2] = {seg_code[data_reg[11:8]], 1'b1};
        end
        else if (control_reg[5:4] == 2'b10) begin
            digit_data[2] = {seg_code[data_reg[11:8]], 1'b0};
        end
        if (control_reg[7:6] == 2'b01) begin
            digit_data[3] = {seg_code[data_reg[15:12]], 1'b1};
        end
        else if (control_reg[7:6] == 2'b10) begin
            digit_data[3] = {seg_code[data_reg[15:12]], 1'b0};
        end

        if (control_reg[9:8] == 2'b01) begin
            digit_data[4] = {seg_code[data_reg[19:16]], 1'b1};
        end
        else if (control_reg[9:8] == 2'b10) begin
            digit_data[4] = {seg_code[data_reg[19:16]], 1'b0};
        end

        if (control_reg[11:10] == 2'b01) begin
            digit_data[5] = {seg_code[data_reg[23:20]], 1'b1};
        end
        else if (control_reg[11:10] == 2'b10) begin
            digit_data[5] = {seg_code[data_reg[23:20]], 1'b0};
        end

        if (control_reg[13:12] == 2'b01) begin
            digit_data[6] = {seg_code[data_reg[27:24]], 1'b1};
        end
        else if (control_reg[13:12] == 2'b10) begin
            digit_data[6] = {seg_code[data_reg[27:24]], 1'b0};
        end

        if (control_reg[15:14] == 2'b01) begin
            digit_data[7] = {seg_code[data_reg[31:28]], 1'b1};
        end
        else if (control_reg[15:14] == 2'b10) begin
            digit_data[7] = {seg_code[data_reg[31:28]], 1'b0};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_div <= 16'd0;
            scan_idx <= 3'd0;
        end
        else begin
            scan_div <= scan_div + 16'd1;
            if (scan_div == 16'd0) begin
                scan_idx <= scan_idx + 3'd1;
            end
        end
    end

    always @(*) begin
        seg_data = digit_data[scan_idx];
        seg_an = 8'hff;
        seg_an[scan_idx] = 1'b0;
    end

endmodule
