module confreg_monitor (
    input logic       clk,
    input logic       rst_n,
    input logic [7:0] led,
    input logic [7:0] seg_data,
    input logic [7:0] seg_an
);
logic [7:0] led_d;
logic [7:0] seg_data_d;
logic [7:0] seg_an_d;

//数码管
logic [4:0] digit_buf [0:7];
logic       digit_seen[0:7];

logic       an_valid;
logic [2:0] an_idx;
logic [4:0] cur_digit;

int i;
//目前不考虑小数点
function automatic logic [4:0] decode_seg_data(input logic [6:0] seg_code);
    begin
        case (seg_code)
            7'b1000000: decode_seg_data = 5'h0;
            7'b1111001: decode_seg_data = 5'h1;
            7'b0100100: decode_seg_data = 5'h2;
            7'b0110000: decode_seg_data = 5'h3;
            7'b0011001: decode_seg_data = 5'h4;
            7'b0010010: decode_seg_data = 5'h5;
            7'b0000010: decode_seg_data = 5'h6;
            7'b1111000: decode_seg_data = 5'h7;
            7'b0000000: decode_seg_data = 5'h8;
            7'b0010000: decode_seg_data = 5'h9;
            7'b0001000: decode_seg_data = 5'ha;
            7'b0000011: decode_seg_data = 5'hb;
            7'b1000110: decode_seg_data = 5'hc;
            7'b0100001: decode_seg_data = 5'hd;
            7'b0000110: decode_seg_data = 5'he;
            7'b0001110: decode_seg_data = 5'hf;
            default:    decode_seg_data = 5'h1f; // 这里你可以考虑换成单独的 INVALID 编码
        endcase
    end
endfunction
    
// 2. 位选译码
function automatic logic [2:0] decode_seg_an(input logic [7:0] seg_an_val);
    begin
        case (seg_an_val)
            8'b1111_1110: decode_seg_an = 3'd0;
            8'b1111_1101: decode_seg_an = 3'd1;
            8'b1111_1011: decode_seg_an = 3'd2;
            8'b1111_0111: decode_seg_an = 3'd3;
            8'b1110_1111: decode_seg_an = 3'd4;
            8'b1101_1111: decode_seg_an = 3'd5;
            8'b1011_1111: decode_seg_an = 3'd6;
            8'b0111_1111: decode_seg_an = 3'd7;
            default:      decode_seg_an = 3'd0;
        endcase
    end
endfunction

// 3. 判断当前 seg_an 是否是合法单路扫描
function automatic logic is_valid_seg_an(input logic [7:0] seg_an_val);
    begin
        case (seg_an_val)
            8'b1111_1110,
            8'b1111_1101,
            8'b1111_1011,
            8'b1111_0111,
            8'b1110_1111,
            8'b1101_1111,
            8'b1011_1111,
            8'b0111_1111: is_valid_seg_an = 1'b1;
            default:      is_valid_seg_an = 1'b0;
        endcase
    end
endfunction


always_comb begin
    an_valid  = is_valid_seg_an(seg_an);
    an_idx    = decode_seg_an(seg_an);
    cur_digit = decode_seg_data(seg_data[7:1]); // seg_data[0] 是小数点
end


always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led_d[i] <= 0;
        seg_data_d[i] <= 0;
        seg_an_d[i] <= 0;
        for (i = 0; i < 8; i++) begin
            digit_buf[i]  <= 5'd0;
            digit_seen[i] <= 1'b0;
        end
    end else begin
        // 4. LED 变化检测
        for (i = 0; i < 8; i++) begin
            if (led[i] != led_d[i]) begin
                $display("[%0t] LED[%0d] changed: %0b -> %0b", $time, i, led_d[i], led[i]);
            end
        end
        led_d <= led;

        // 5. 数码管变化检测
        if (an_valid) begin
            // 第一次扫到这一位，只记录，不一定打印
            if (!digit_seen[an_idx]) begin
                digit_buf[an_idx]  <= cur_digit;
                digit_seen[an_idx] <= 1'b1;
            end
            // 后续扫到这一位，如果值变了才打印
            else if (digit_buf[an_idx] != cur_digit) begin
                $display("[%0t] SEG[%0d] changed: %0h -> %0h (an=%b, data=%b)",
                         $time, an_idx, digit_buf[an_idx], cur_digit, seg_an, seg_data);
                digit_buf[an_idx] <= cur_digit;
            end
        end


        seg_an_d   <= seg_an;
        seg_data_d <= seg_data;
    end
    end


endmodule
