module smg_control_module
(
input sys_clk,
 input rst_n,
 input [24:0]Number_Sig,
 output [3:0]Number_Data
);
/*
	 
	 parameter T1MS = 16'd49999;            //1ms计数
	 
	 
	  reg [15:0]C1;
	 
	 always @ ( posedge sys_clk or negedge rst_n )
	     if( !rst_n )
		      C1 <= 16'd0;
		  else if( C1 == T1MS )
		      C1 <= 16'd0;
		  else
		      C1 <= C1 + 1'b1;
	  
	 reg [3:0]i;
	 reg [3:0]rNumber;
	 
	 always @ ( posedge sys_clk or negedge rst_n )
	     if( !rst_n )
		      begin
		          i <= 4'd0;
			    	 rNumber <= 4'd0;
				end
		  else 
		      case( i )
				
				    0:
					 if( C1 == T1MS ) i <= i + 1'b1;
					 else if(Number_Sig[24])
					      rNumber <= 4'hf; 
					 else rNumber <= Number_Sig[23:20];          //十万位数码管显示           
	
					 1:
					 if( C1 == T1MS ) i <= i + 1'b1;
					 else rNumber <= Number_Sig[19:16];          //万位数码管显示
					 
					 2:
					 if( C1 == T1MS ) i <= i + 1'b1;
					 else rNumber <= Number_Sig[15:12];          //千位数码管显示
					 
					 3:
					 if( C1 == T1MS ) i <= i + 1'b1;
					 else rNumber <= Number_Sig[11:8];           //百位数码管显示
					 
					 4:
					 if( C1 == T1MS ) i <= i + 1'b1;
					 else rNumber <= Number_Sig[7:4];            //十位数码管显示
					 
					 5:
					 if( C1 == T1MS ) i <= 4'd0;
					 else rNumber <= Number_Sig[3:0];            //低位数码管显示
				
				endcase
				
	 
	 assign Number_Data = rNumber;
*/
parameter T1MS        = 16'd49999;            //1ms count
parameter IDLE         =6'b000001;
parameter ST1          =6'b000010;
parameter ST2          =6'b000100;
parameter ST3          =6'b001000;
parameter ST4          =6'b010000;
parameter ST5          =6'b100000;

reg [15:0]             time_cnt;               //time count
reg [5:0]              cur_state;
reg [5:0]              next_state;
reg [3:0]              rNumber;
assign Number_Data = rNumber; 

always@(posedge sys_clk)
begin 
if(!rst_n)
    cur_state<=IDLE;
 else
    cur_state<=next_state;
end

//time count
always @ ( posedge sys_clk or negedge rst_n )
if( !rst_n )
  time_cnt <= 16'd0;
else if( time_cnt == T1MS )
  time_cnt <= 16'd0;
else
  time_cnt <= time_cnt + 1'b1;
 
 always @ ( time_cnt or cur_state )
begin
  case(cur_state)    
      IDLE:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST1;
             else
                next_state<=IDLE;
         end          
      ST1:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST2;
             else
                next_state<=ST1;
         end    
      ST2:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST3;
             else
                next_state<=ST2;
         end     
       ST3:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST4;
             else
                next_state<=ST3;
         end    
      ST4:
         begin
            if(time_cnt== T1MS ) 
                next_state<=ST5;
             else
                next_state<=ST4;
            end
      ST5:
         begin
            if(time_cnt== T1MS ) 
                next_state<=IDLE;
             else
                next_state<=ST5;
         end
       default: next_state<=IDLE;                
    endcase
end
always @ ( posedge sys_clk or negedge rst_n )
  begin
    if( !rst_n )
      begin
          rNumber <= 4'd0;
        end
    else 
      case(next_state)
           IDLE:
              begin
                 if(Number_Sig[24])
					 rNumber <= 4'hf; 
				  else 
					 rNumber <= Number_Sig[23:20]; //sixth digital tube display              
               end      
             ST1:
                 rNumber <= Number_Sig[19:16];          //fifth digital tube display
             ST2:
                 rNumber <= Number_Sig[15:12];          //fourth digital tube display
             ST3:
                 rNumber <= Number_Sig[11:8];           //third digital tube display
             ST4:
                 rNumber <= Number_Sig[7:4];            //second digital tube display
             ST5:
                 rNumber <= Number_Sig[3:0];            //first digital tube display
             default: 
                 rNumber <= 4'd0;                        
        endcase
  end  	 
endmodule
