// 
// Copyright 2013 Jeff Bush
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 

//
// A cluster is the group of processors and global memory that is shared
// between them.
//

`include "config.v"

module cluster
    #(parameter NUM_CORES = 16)

    (input          clk, // 클락
    input           reset, // 리셋
    input  [15:0]   device_data_in, // 외부 메모리에서 읽은 데이터
    output          device_write_en, // 외부 메모리 쓰기 활성화
    output          device_read_en, // 외부 메모리 읽기 활성화
    output [9:0]    device_addr, // 외부 메모리에 접근할 어드레스
    output [15:0]   device_data_out, // 외부 메모리에 쓸 데이터
    output reg [$clog2(NUM_CORES) - 1:0] device_core_id, // 코어 id

    input           axi_we, // response
    input  [15:0]   axi_addr, // response
    input  [15:0]   axi_data, // response
    output [15:0]   axi_q); // ?
    
	//---
	
    localparam LOCAL_MEMORY_SIZE = 512; // 지역 메모리 크기
    localparam GLOBAL_MEMORY_SIZE = 1024; // 전역 메모리 크기
    localparam GMEM_ADDR_WIDTH = $clog2(GLOBAL_MEMORY_SIZE); // 전역 메모리 어드레스 위드
    
    wire[15:0] memory_addr; // 접근할 메모리의 주소
    wire[15:0] core_memory_addr [0:NUM_CORES-1]; // 메모리 주소를 코어별로 따로 저장
    
    wire[15:0] memory_read_val; // 메모리에서 읽은 데이터
    
    wire memory_wren; // 메모리 쓰기 신호
    wire core_memory_wren [NUM_CORES-1:0]; // 코어별로 따로 저장
    
    wire memory_rden; // 메모리 읽기 신호
    wire core_memory_rden [NUM_CORES-1:0]; // 코어별로 따로 저장
    
    wire[15:0] memory_write_val; // 메모리에 쓸 데이터
    wire[15:0] core_memory_write_val[0:NUM_CORES-1]; // 코어별로 따로 저장
    
    wire[15:0] global_mem_q; // 글로벌 메모리에서 읽은 데이터
    wire device_memory_select; // 메모리 어드레스에 따라 접근할 메모리가 다른데, 그 selector임.
    reg device_memory_select_l; // 외부 메모리에서 읽은 데이터냐 글로벌 메모리에서 읽은 데이터냐
    wire global_mem_write; // 글로벌 메모리가 선택되어져 있으면서 메모리 쓰기가 활성화되어 있으면? = 글로벌 메모리 쓰기 활성화!
    wire[NUM_CORES-1:0] core_enable; // 글로벌 메모리에 접근할 권한 같음. 잘은 모르겠음
    wire[NUM_CORES-1:0] core_request; // 글로벌 메모리 접근 요청
    
	//---
	
    assign memory_wren = core_memory_wren[device_core_id]; // 선택된 코어의 wren rden addr val을 select하는 과정
    assign memory_rden = core_memory_rden[device_core_id];
    assign memory_addr = core_memory_addr[device_core_id];
    assign memory_write_val = core_memory_write_val[device_core_id]; // device_core_id번 코어의 write_val을 활성화하겠다는 뜻.

    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1)
        begin: core
            core #(LOCAL_MEMORY_SIZE) inst ( // ★★
                .clk(clk),
                .reset(reset),
                .core_enable(core_enable[i]), // 각 코어의 input/output을 wire로 가지고 있음
                .core_request(core_request[i]),
                .memory_addr(core_memory_addr[i]),
                .memory_wren(core_memory_wren[i]),    
                .memory_rden(core_memory_rden[i]),
                .memory_write_val(core_memory_write_val[i]),
                .memory_read_val(memory_read_val));
        end
    endgenerate

    assign device_memory_select = memory_addr[15:10] == 6'b111111; // 메모리 주소에 따라 다른 디바이스에서 가져옴
    assign device_addr = memory_addr[9:0]; // 1KB 크기.
    assign global_mem_write = !device_memory_select && memory_wren; // !device_memory_select는 global_memory_select와 같음, 즉 global_memory_select and global_memory_wren
    assign memory_read_val = device_memory_select_l ? device_data_in : global_mem_q; // 외부 메모리에서 가져온 데이터를 취할지 글로벌 메모리에서 가져온 데이터를 취할지
    assign device_write_en = device_memory_select && memory_wren; // 마찬가지로 외부 메모리면서 wren이면
    assign device_read_en = device_memory_select && memory_rden; // 마찬가지로 rden
    assign device_data_out = memory_write_val; // 디바이스에 쓸 데이터. device 관련 모든 wire들은 output으로 axi로 들어감

    // Convert one-hot to binary = encoding?
    integer oh_index;
    always @*
    begin : convert
        device_core_id = 0;
        for (oh_index = 0; oh_index < NUM_CORES; oh_index = oh_index + 1)
        begin
            if (core_enable[oh_index])
            begin : convert
                 // Use 'or' to avoid synthesizing priority encoder
                device_core_id = device_core_id | oh_index[$clog2(NUM_CORES) - 1:0];
            end
        end
    end

    dpsram 
`ifdef FEATURE_FPGA
    #(GLOBAL_MEMORY_SIZE, 16, GMEM_ADDR_WIDTH, 1, `PROGRAM_PATH) 
`else
    #(GLOBAL_MEMORY_SIZE, 16, GMEM_ADDR_WIDTH) 
`endif
    global_memory(
        .clk(clk),
        //Port A
        .addr_a(memory_addr[GMEM_ADDR_WIDTH - 1:0]),
        .q_a(global_mem_q),
        .we_a(global_mem_write),
        .data_a(memory_write_val),
        //Port B
        .addr_b(axi_addr[GMEM_ADDR_WIDTH - 1:0]),
        .q_b(axi_q),
        .we_b(axi_we),
        .data_b(axi_data));

    always @(posedge reset, posedge clk)
    begin
        if (reset)
            device_memory_select_l <= 0;
        else 
            device_memory_select_l <= device_memory_select;
    end

`ifdef STATIC_ARBITRATION
    reg[NUM_CORES - 1:0] core_enable_ff;
    
    assign core_enable = core_enable_ff;

    always @(posedge reset, posedge clk)
    begin
        if (reset)
            core_enable_ff <= {{NUM_CORES - 1{1'b0}}, 1'b1};
        else 
            core_enable_ff = { core_enable_ff[NUM_CORES - 2:0], core_enable_ff[NUM_CORES - 1] };
    end
`else
    arbiter #(NUM_CORES) global_mem_arbiter(
        .clk(clk),
        .reset(reset),
        .request(core_request),
        .grant_oh(core_enable));
`endif
endmodule
