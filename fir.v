`timescale 1ns / 1ps

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,
    input   wire                     ss_tvalid,
    input   wire [(pDATA_WIDTH-1):0] ss_tdata,
    input   wire                     ss_tlast,
    output  wire                     ss_tready,
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast,
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,
    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
begin
    // write your code here!
    // FSM:　AXI_Stream
    reg [1:0] S_state_current, S_state_next;
    reg [1:0] S_IDLE = 2'd0;
    reg [1:0] S_LOAD = 2'd1;
    reg [1:0] S_CAL  = 2'd2;
    reg [1:0] S_DONE = 2'd3;
    //FSM: AXI_Lite
    reg [2:0] L_state_current, L_state_next;
    reg [2:0] L_IDLE  = 3'b000;
    reg [2:0] L_RADDR = 3'b010;
    reg [2:0] L_RDATA = 3'b011;
    reg [2:0] L_WADDR = 3'b100;
    reg [2:0] L_WDATA = 3'b101;

    reg [3:0] data_first, data_count;
    reg       data_last, data_rst, ss_tready_temp, sm_tvalid_temp;
    wire[3:0] data_index;    
    reg signed [31:0] MAC;
    reg [(pDATA_WIDTH-1):0] data_state, data_length;

    assign ss_tready  = ss_tready_temp;
    assign sm_tvalid  = sm_tvalid_temp;
    assign sm_tdata   = MAC;
    assign sm_tlast   = data_last;
	assign arready = (L_state_current == L_RADDR) ? 1 : 0;
	assign awready = (L_state_current == L_WADDR) ? 1 : 0;
    assign rdata   = (L_state_current == L_RDATA) ? (araddr == 32'h0000)? data_state: (araddr == 32'h00010)? data_length : (araddr >= 32'h0020)? tap_Do:0 : 0;
	assign rvalid  = (L_state_current == L_RDATA) ? 1 : 0;
	assign wready  = (L_state_current == L_WDATA) ? 1 : 0;

    always@(posedge axis_clk, negedge axis_rst_n) begin
		if (!axis_rst_n) begin
            data_last <= 0;
            data_rst <= 0;
            ss_tready_temp <= 0;
            sm_tvalid_temp <= 0;
            data_first <= 0;
            data_count <= 0;
            MAC <= 0;
            S_state_current <= S_IDLE;
            L_state_current <= L_IDLE;
		end 
        else begin 
            S_state_current <= S_state_next;
            L_state_current <= L_state_next; 
            case(S_state_current)
                S_IDLE:begin
                    ss_tready_temp <= 0;
                    sm_tvalid_temp <= 0;
                    data_first <= (data_rst)? 0 : data_first+1;
                    data_rst <= (data_rst)? 1:(data_first==10)? 1:0;
                end
                S_LOAD:begin
                    ss_tready_temp <= 1;
                    sm_tvalid_temp <= 0;
                    data_count <= 1;
                end
                S_CAL:begin
                    ss_tready_temp <= 0;
                    sm_tvalid_temp <= (data_count==11)? 1:0;
                    data_count <= (data_count==11)? 0 : data_count+1;
                    MAC <= MAC + $signed(tap_Do) * $signed(data_Do);
                end
                S_DONE:begin
                    ss_tready_temp <= 0;
                    sm_tvalid_temp <= 0;                   
                    data_first <= (data_first==10)? 0 : data_first+1;
                    MAC <= 0;
                    data_last <= (ss_tlast)? 1:0;
                end
            endcase
		end 
	end
    assign data_index = (data_first >= data_count)? (data_first - data_count) : 11-(data_count - data_first);

    always@(*)begin
        case(S_state_current)
            S_IDLE: S_state_next = (data_state[0])? S_LOAD:S_IDLE;
            S_LOAD: S_state_next = S_CAL;
            S_CAL: S_state_next = (data_count==11)? S_DONE:S_CAL;
            S_DONE: S_state_next = (data_last)? S_IDLE:S_LOAD;
        endcase
        case(L_state_current)
            L_IDLE: L_state_next = (awvalid)? L_WADDR : (arvalid)? L_RADDR :  L_IDLE; 
            L_RADDR: L_state_next = (arvalid && arready)? L_RDATA : L_RADDR;
            L_RDATA: L_state_next = (rready && rvalid)? L_IDLE : L_RDATA;
            L_WADDR: L_state_next = (awvalid && awready)? L_WDATA : L_WADDR; 
            L_WDATA: L_state_next = (wready && wvalid)? L_IDLE : L_WDATA;
        endcase
    end

    always @(posedge  axis_clk) begin
		if (!axis_rst_n) begin
			data_state <= 32'h0000_0004;
            data_length <= 0;
		end else begin
			if (L_state_current == L_WDATA) begin
                if (awaddr == 32'h0000) data_state <= wdata;
                else if(awaddr == 32'h0010) data_length <= wdata;
            end
            else if (L_state_current == L_RDATA) data_state[1] <= (awaddr == 32'h0000)? 0:data_state[1];
            else begin
                data_state[0] <= (!data_state[0])? 0:(S_state_current == S_IDLE)? 1:0;
                data_state[1] <= (data_state[1])? 1:(data_last==1 && S_state_current==S_DONE)? 1:0;
                data_state[2] <= (data_state[2])? (data_state[0]==1)? 0:1 : (ss_tlast==1 && S_state_current==S_IDLE)? 1:0;
            end
		end
	end

    assign tap_EN = 1;
    assign tap_WE = (L_state_current == L_WDATA && awaddr >= 32'h0020)? 4'b1111:0;
    assign tap_Di = wdata;
    assign tap_A = (L_state_current==L_WDATA && S_state_current==S_IDLE)? awaddr-32'h0020 : (L_state_current==L_RADDR && S_state_current==S_IDLE)? araddr-32'h0020 : (data_count<<2);

    assign data_EN = 1;
    assign data_WE = (S_state_current==S_IDLE || S_state_current==S_LOAD)? 4'b1111:0;
    assign data_Di = (S_state_current == S_IDLE)? 0 : ss_tdata;
    assign data_A = (S_state_current==S_CAL)? (data_index<<2) : (data_first<<2);

end
endmodule