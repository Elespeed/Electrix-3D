// Four-stage registered transform.  Separating yaw, pitch, roll and scale
// keeps a BRAM-read-to-BRAM-write Scene vertex below the 50 MHz sys_clk budget.
module scene_ctrl_vertex_transform (
    input logic clk, input logic resetn, input logic in_valid,
    input logic [15:0] vx, input logic [15:0] vy, input logic [15:0] vz,
    input logic [3:0] yaw, input logic [3:0] pitch, input logic [3:0] roll,
    input logic [15:0] scale, input logic signed [15:0] translate_x, input logic signed [15:0] translate_y, input logic signed [15:0] translate_z,
    output logic out_valid,
    output logic signed [25:0] x, output logic signed [25:0] y, output logic signed [25:0] z
);
    import scene_ctrl_math_pkg::*;
    logic v0, v1, v2;
    logic signed [35:0] yaw_x_q, yaw_y_q, yaw_z_q;
    logic signed [35:0] pitch_x_q, pitch_y_q, pitch_z_q;
    logic signed [35:0] roll_x_q, roll_y_q, roll_z_q;
    logic [3:0] pitch_q0, roll_q0, roll_q1;
    logic [15:0] scale_q0, scale_q1, scale_q2;
    logic signed [15:0] translate_x_q0, translate_x_q1, translate_x_q2, translate_y_q0, translate_y_q1, translate_y_q2, translate_z_q0, translate_z_q1, translate_z_q2;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            v0 <= 0; v1 <= 0; v2 <= 0; out_valid <= 0;
            x <= 0; y <= 0; z <= 0;
        end else begin
            v0 <= in_valid;
            if (in_valid) begin
                yaw_x_q <= (($signed(vx) * $signed(sin16(yaw + 4))) + ($signed(vz) * $signed(sin16(yaw)))) >>> 14;
                yaw_y_q <= $signed(vy) >>> 8;
                yaw_z_q <= ((-$signed(vx) * $signed(sin16(yaw))) + ($signed(vz) * $signed(sin16(yaw + 4)))) >>> 14;
                pitch_q0 <= pitch; roll_q0 <= roll; scale_q0 <= scale; translate_x_q0 <= translate_x; translate_y_q0 <= translate_y; translate_z_q0 <= translate_z;
            end

            v1 <= v0;
            if (v0) begin
                pitch_x_q <= yaw_x_q;
                pitch_y_q <= (yaw_y_q * $signed(sin16(pitch_q0 + 4)) - yaw_z_q * $signed(sin16(pitch_q0))) >>> 6;
                pitch_z_q <= (yaw_y_q * $signed(sin16(pitch_q0)) + yaw_z_q * $signed(sin16(pitch_q0 + 4))) >>> 6;
                roll_q1 <= roll_q0; scale_q1 <= scale_q0; translate_x_q1 <= translate_x_q0; translate_y_q1 <= translate_y_q0; translate_z_q1 <= translate_z_q0;
            end

            v2 <= v1;
            if (v1) begin
                roll_x_q <= (pitch_x_q * $signed(sin16(roll_q1 + 4)) - pitch_y_q * $signed(sin16(roll_q1))) >>> 6;
                roll_y_q <= (pitch_x_q * $signed(sin16(roll_q1)) + pitch_y_q * $signed(sin16(roll_q1 + 4))) >>> 6;
                roll_z_q <= pitch_z_q;
                scale_q2 <= scale_q1; translate_x_q2 <= translate_x_q1; translate_y_q2 <= translate_y_q1; translate_z_q2 <= translate_z_q1;
            end

            out_valid <= v2;
            if (v2) begin
                x <= ((roll_x_q * $signed({1'b0, scale_q2})) >>> 8) + translate_x_q2;
                y <= ((roll_y_q * $signed({1'b0, scale_q2})) >>> 8) + translate_y_q2;
                z <= ((roll_z_q * $signed({1'b0, scale_q2})) >>> 8) + translate_z_q2;
            end
        end
    end
endmodule
