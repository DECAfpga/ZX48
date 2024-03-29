// ZX48 VGA for DECA by Somhic
// Adapted from KYP's ua2 port (Unamiga) https://github.com/Kyp069/zx48 
// v1 video modified to work with VGA 333
// v2 changed to video from ZXuno port which is VGA 333
// v3 I2S Audio though DECA DAC TLV320AIC3254
// v4 EAR and Joystick support  (UDLR + 2 buttons)
// v5.0 Revised qsf pinout. Added pinout. Sound fixes. RGB/VGA changes with Scroll lock key
// 
// TO DO LIST
// - With DECA SDRAM settings (zx48 (settings-sdram).qsf) core hungs. Try clkram with phase=-1.5ns
// - Adapt original constraints from zx48.old.sdc into zx48.sdc
//

//-------------------------------------------------------------------------------------------------
module zx48
//-------------------------------------------------------------------------------------------------
(
	input  wire       clock50,

	output wire[ 1:0] led,

	//debug
	output wire 	debugled,
	input wire		KEY0,

	output wire[ 1:0] sync,
	output wire[8:0]  rgb,

	output wire       i2sMck,	//AUDIO_MCLK
	output wire       i2sSck,	//AUDIO_BCLK
	output wire       i2sLr,	//AUDIO_WCLK
	output wire       i2sD,		//AUDIO_DIN_MFP1

	input  wire       ear,		
	
	// Audio DAC DECA
	inout wire 		AUDIO_GPIO_MFP5,
	input wire 		AUDIO_MISO_MFP4,
	inout wire 		AUDIO_RESET_n,
	output wire 	AUDIO_SCLK_MFP3,
	output wire 	AUDIO_SCL_SS_n,
	inout wire 		AUDIO_SDA_MOSI,
	output wire 	AUDIO_SPI_SELECT,

	inout  wire       keybCk,
	inout  wire       keybDQ,

	input  wire[ 5:0] jstick1,
	output wire       joy_sel_o,

	output wire       sdramCk,
	output wire       sdramCe,
	output wire       sdramCs,
	output wire       sdramWe,
	output wire       sdramRas,
	output wire       sdramCas,
	output wire[ 1:0] sdramDQM,
	inout  wire[15:0] sdramDQ,
	output wire[ 1:0] sdramBA,
	output wire[12:0] sdramA,

	output wire       usdCs,
	output wire       usdCk,
	input  wire       usdMiso,
	output wire       usdMosi,
	// SD DECA
	output wire   	SD_SEL,
	output wire		SD_CMD_DIR,
	output wire		SD_D0_DIR,
	output wire		SD_D123_DIR
	
);

//-------------------------------------------------------------------------------------------------

wire clock, locked;
wire reset_n;
assign reset_n = KEY0;


clock Clock (
	.inclk0 (clock50),   // 50 MHz input
	.areset(!reset_n),
	.c0     (clock  ),   // 56 MHz output
	.locked (locked )
	);

reg[3:0] pw = 0;
wire power = pw[3];
always @(posedge clock) if(locked) if(!power) pw <= pw+1'd1;

reg[2:0] cc = 0;
always @(negedge clock) if(power) cc <= cc+1'd1;

wire ne28M = power & ~cc[0];
wire ne14M = power & ~cc[0] & ~cc[1];
wire ne7M0 = power & ~cc[0] & ~cc[1] & ~cc[2];

//-------------------------------------------------------------------------------------------------

  // MicroSD Card 
  assign SD_SEL = 1'b0;   //0 = 3.3V at sdcard	
  assign SD_CMD_DIR = 1'b1;  // MOSI FPGA output	
  assign SD_D0_DIR = 1'b0;   // MISO FPGA input	
  assign SD_D123_DIR = 1'b1; // CS FPGA output	
  // 

wire[7:0] code;
wire kstb, make;

ps2 PS2
(
	.clock  (clock  ),
	.ce     (ne7M0  ),
	.ps2Ck  (keybCk ),
	.ps2DQ  (keybDQ ),
	.kstb   (kstb   ),
	.make   (make   ),
	.code   (code   )
);

reg F5 = 1'b1;
reg F12 = 1'b1;
reg del = 1'b1;
reg alt = 1'b1;
reg ctrl = 1'b1;
reg scrlck = 1'b1;

always @(posedge clock) if(kstb)
case(code)
	8'h03: F5  <= make;
	8'h07: F12 <= make;
	8'h71: del <= make;
	8'h11: alt <= make;
	8'h14: ctrl <= make;
	8'h7E: scrlck <= make;
endcase

//-------------------------------------------------------------------------------------------------

wire reset = power & ready & F12 & (ctrl|alt|del);
wire nmi = F5;

wire[11:0] laudio;
wire[11:0] raudio;

wire[7:0] joy1 = { 2'd0, ~jstick1 };
/*
0 - Nada
1 - Derecha		jstick1[0]
2 - Izquierda	jstick1[1]
4 - Abajo		jstick1[2]
8 - Arriba		jstick1[3]
16 - Disparo A	jstick1[4]
32 - Disparo B	jstick1[5]
*/

assign joy_sel_o = 1'b1;

wire[ 7:0] ramD;
wire[ 7:0] ramQ = sdrQ[7:0];
wire[17:0] ramA;

wire       blank;
wire hsync, vsync;
wire r,g,b,i;
wire rfsh, map, ramRd, ramWr;

main Main
(
	.clock  (clock  ),
	.power  (power  ),
	.reset  (reset  ),
	.rfsh   (rfsh   ),
	.nmi    (nmi    ),
	.map    (map    ),
	.blank  (blank  ),
	.hsync  (hsync  ),
	.vsync  (vsync  ),
	.r      (r      ),
	.g      (g      ),
	.b      (b      ),
	.i      (i      ),
	.ear    (~ear   ),
	.laudio (laudio ),
	.raudio (raudio ),
	.kstb   (kstb   ),
	.make   (make   ),
	.code   (code   ),
	.joy1   (joy1   ),
	.cs     (usdCs  ),
	.ck     (usdCk  ),
	.miso   (usdMiso),
	.mosi   (usdMosi),
	.ramRd  (ramRd  ),
	.ramWr  (ramWr  ),
	.ramD   (ramD   ),
	.ramQ   (ramQ   ),
	.ramA   (ramA   )
);

//-------------------------------------------------------------------------------------------------

wire sdrRf = rfsh;
wire sdrRd = ramRd;
wire sdrWr = ramWr;

wire[15:0] sdrD = {2{ramD}};
wire[15:0] sdrQ;
wire[23:0] sdrA = { 6'd0, ramA };
wire ready;

sdram SDram
(
	.clock   (clock   ),
	.reset   (power   ),
	.ready   (ready   ),
	.refresh (sdrRf   ),
	.write   (sdrWr   ),
	.read    (sdrRd   ),
	.portD   (sdrD    ),
	.portQ   (sdrQ    ),
	.portA   (sdrA    ),
	.sdramCs (sdramCs ),
	.sdramRas(sdramRas),
	.sdramCas(sdramCas),
	.sdramWe (sdramWe ),
	.sdramDQM(sdramDQM),
	.sdramDQ (sdramDQ ),
	.sdramBA (sdramBA ),
	.sdramA  (sdramA  )
);

assign sdramCk = clock;
assign sdramCe = 1'b1;

//-------------------------------------------------------------------------------------------------
   // Audio DAC DECA 
   
   //--RESET DELAY ---
   reg RESET_DELAY_n;
   reg   [31:0]  DELAY_CNT;   
   assign debugled = RESET_DELAY_n;

	always @(negedge reset ) begin 
	if ( reset )  begin 
			RESET_DELAY_n <= 0;
			DELAY_CNT   <= 0;
		end 
	else  begin 
			if ( DELAY_CNT < 32'hfffff  )  
				DELAY_CNT <= DELAY_CNT+1; 
			else 
				RESET_DELAY_n <= 1;
		end
	end

    // Audio DAC DECA Output assignments
    assign AUDIO_GPIO_MFP5  = 1;  // GPIO
    assign AUDIO_SPI_SELECT = 1;  // SPI mode
    assign AUDIO_RESET_n    = RESET_DELAY_n;   

    // AUDIO CODEC SPI CONFIG
    // I2S mode; fs = 48khz; MCLK = 24.567MhZ x 2
    AUDIO_SPI_CTL_RD u1 (
        .iRESET_n(RESET_DELAY_n), 
        .iCLK_50(clock50),		  //50Mhz clock
        .oCS_n(AUDIO_SCL_SS_n),   //SPI interface mode chip-select signal
        .oSCLK(AUDIO_SCLK_MFP3),  //SPI serial clock
        .oDIN(AUDIO_SDA_MOSI),    //SPI Serial data output
        .iDOUT(AUDIO_MISO_MFP4)   //SPI serial data input
    );
    
//-------------------------------------------------------------------------------------------------

//  I2S AUDIO 
wire[15:0] ldata = { laudio, 4'b0000 };
wire[15:0] rdata = { raudio, 4'b0000 };

i2s I2S
(
	.clock  (clock  ),
	.ldata  (ldata  ),
	.rdata  (rdata  ),
	.mck    (i2sMck ),
	.sck    (i2sSck ),
	.lr     (i2sLr  ),
	.d      (i2sD   )
);

//-------------------------------------------------------------------------------------------------

// this part ported from zxuno
wire[8:0] irgb = blank ? 9'd0 : { r,i&r,r, g,i&g,g, b,i&b,b };
wire[8:0] orgb;

scandoubler #(.RGBW(9)) Scandoubler
(
	.clock  (clock  ),
	.ice    (ne7M0  ),
	.ihs    (hsync  ),
	.ivs    (vsync  ),
	.irgb   (irgb   ),
	.oce    (ne14M  ),
	.ohs    (ohsync ),
	.ovs    (ovsync ),
	.orgb   (orgb   )
);


//key BLOQ DESP changes mode from VGA to RGB. vga = 1 defalts to VGA.
reg vga = 1'b1;
reg scrlckd = 1'b1;

always @(posedge clock) if(kstb)
begin
	scrlckd <= scrlck;
	if(!scrlck && scrlckd) vga <= ~vga;
end

//-------------------------------------------------------------------------------------------------

assign led = { ~usdCs, map };

assign sync = vga ? { ovsync, ohsync } : { 1'b1, ~(hsync^vsync) };
assign rgb = vga ? orgb : irgb;

endmodule
