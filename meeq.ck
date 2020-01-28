// =========================================================================================
// Name:        meeq; a monome midi step sequencer
// Version:     v1.0
// Date:        February 3rd 2009
// Author:      Graham Morrison
// Email:       meeq@paldandy.com
// Web:         http://www.paldandy.com
// Licence:     GPLv3; http://www.gnu.org/licenses
//
// Description: A multi-layered, polyphonic, polyrhythmic and dynamic MIDI step sequencer
// Features:    Forward, backward and random play. Allows dynmic adjustment of step sizes,
//              timing, MIDI channels and manual scales, plus both short and sustained notes
// Prefix:      /meeq
//
// Credits:     1. MIDI Note section taken from Bruce Murphy's Basic Midi Wrapper class for
//              Chuck. See http://www.rattus.net/~packrat/audio/ChucK/files/midisender.ck
// =========================================================================================

//
// QUICK SETUP INSTRUCTIONS:
// NOTE: Only works from the command-line version of Chuck and not the miniAudicle GUI.
//       Chuck needs to be installed and in your path.
//
// 1. Find the MIDI device name you want to output notes to by typing:
//      chuck --probe
//
// 2. Copy the device name within the double quotes into following line:
//"PLACE DEVICE NAME HERE" => string midioutstring;
//"USB Midi Cable" => string midioutstring;
//"IAC IAC 1" => string midioutstring;
"IAC Driver Bus 1" => string midioutstring;
//"BCF2000 Port 3"  => string midioutstring;
//
// 3. Define the dimensions of your monome. Maxx holds the width, while maxy hold the height
//    eg. for monome 64
//          08 => int maxx;
//          08 => int maxy;
//        for monome 128
//          16 => int maxx;
//          08 => int maxy;
16 => int maxx;
08 => int maxy;

// Default brightness
15 => int brightness;

//
// 4. Set the global tempo for meeq by changing 120 in the following line:
102 => int bpm;
//
// 5. Run MonomeSerial and set the prefix to /meeq
//
//
//
// 6. Type 'chuck meeq_v1.ck' on the command-line to run the sequencer.
//
// END OF QUICK SETUP INSTRUCTIONS


/// Enable or disable Octomod support
0 => int enable_octomod;

/// Enable or disable voltage pulse for CV sync
0 => int enable_clockpulse;

/// Enable or disable a layer's notes triggering voltage pulse
/// This defaults to layer nine
0 => int enable_layerpulse;
8 => int pulse_layer;

/// Button Configuration (x, y)
[maxx-2,0] @=> int key_random[];
[maxx-3,0] @=> int key_forwards[];
[maxx-4,0] @=> int key_backwards[];
[maxx-1,1] @=> int key_step_size[];
[maxx-1,2] @=> int key_time[];
[maxx-1,3] @=> int key_volume[];
[maxx-1,4] @=> int key_transpose[];
[maxx-1,5] @=> int key_scale[];
[maxx-1,6] @=> int key_swing[];
[maxx-1,6] @=> int key_channel[];
[maxx-1,7] @=> int key_mute[];

/// Button Configuration for overlays
[maxx-1,0] @=> int key_clear_pattern[];	        // Global settings overlay
[maxx-1,1] @=> int key_glfo[];			// Global LFO settings
[maxx-1,4] @=> int key_lfo[];			// LFO modulation amount layer
[maxx-1,5] @=> int key_prb[]; 		 	// Probability layer
[maxx-1,6] @=> int key_cc1[];			// MIDI Control Layer 1
[maxx-1,7] @=> int key_cc2[];			// MIDI Control Layer 2

/// Button Configuration for layer switching
[0,0]   @=> int key_layer_0[];
[1,0]   @=> int key_layer_1[];
[2,0]   @=> int key_layer_2[];
[3,0]   @=> int key_layer_3[];

/// A crude hack so that unused layer keys
/// are defined out of range on smaller Monomes
[maxx-12,0]   @=> int key_layer_4[];
[maxx-11,0]   @=> int key_layer_5[];
[maxx-10,0]   @=> int key_layer_6[];
[maxx-9 ,0]   @=> int key_layer_7[];
[maxx-8 ,0]   @=> int key_layer_8[];
[maxx-7, 0]   @=> int key_layer_9[];
[maxx-6, 0]   @=> int key_layer_10[];
[maxx-5, 0]   @=> int key_layer_11[];

// LFO Modulation layer - global values
50 => int glfo_sample_latency;	// LFO latency for sampling - affects display update
08  => int maxlfo;				// Max number of LFOs
modLFO lfo[maxlfo];				// Create  LFOs

/// free-running oscillators
for (0 => int i; i<maxlfo; i++){
	spork ~lfo_generator(i);
}

spork ~lfo_sampler(maxlfo);
//spork ~lfo_backgroundUpdate();

/// Scales Object
mScales mscale;

/// MIDI: Search through MIDI devices for one that matches the pre-configured name
MidiOut mout;
MidiMsg msg;

int rate, position;
12 => int layers;

/// MIDI control numbers for the two control overlays
1 => int cc1; // Modulation wheel
2 => int cc2; // Aftertouch

1 => int short_note;
2 => int long_note;

0 => int current_matrix;

mChannel midiChannel[16];
noteGrid grid[layers];

/// Deal with command-line arguments (probably sent from the GUI)
/// for example: maxx:maxy:midi device:bpm:cc1:cc2
/// should look like:
/// chuck meeq.ck:16:8:0:120:71:41

if( me.args() ){

	Std.atoi(me.arg(0)) => maxx; 						/// width
	Std.atoi(me.arg(1)) => maxy; 						/// height
	if (!mout.open(Std.atoi(me.arg(4)))) me.exit();		/// MIDI device
	Std.atoi(me.arg(5)) => bpm;							/// BPM
	Std.atoi(me.arg(6)) => cc1;							/// CC1
	Std.atoi(me.arg(7)) => cc2;							/// CC2

} else {

	for(0 => int i; true ; i++){
	   if (!mout.open(i)) me.exit();
	   if (mout.name() == midioutstring) break;
	}

}

<<< "MIDI Output device:", mout.num(), " -> ", mout.name() >>>;

/// Create OSC connections
/// Requires: serial-osc

"/meeq" => string prefix;

//Osc send/recv for Monome
"localhost" => string host;
12002 => int hostport;
8000 => int receiveport;

// initial send and recieve
OscSend xmit;
xmit.setHost(host, hostport);

OscRecv recv;
receiveport => recv.port;
recv.listen();

//list devices
xmit.startMsg("/serialosc/list", "si");
host  => xmit.addString;
receiveport => xmit.addInt;

   <<<"looking for a monome...", "">>>;

recv.event("/serialosc/device", "ssi") @=> OscEvent discover;
discover => now;

string serial; string devicetype; int port;

while(discover.nextMsg() != 0){

        discover.getString() => serial;
        discover.getString() => devicetype;
        discover.getInt() => port;

        <<<"connecting to", devicetype, "(", serial, ") on port", port>>>;
}

//connect to device
xmit.setHost(host, port);
xmit.startMsg("/sys/port", "i");
receiveport => xmit.addInt;

//get size
recv.event("/sys/size", "ii") @=> OscEvent getsize;

xmit.startMsg("/sys/info", "si");
host => xmit.addString;
receiveport => xmit.addInt;

getsize => now;

int width; int height;

while(getsize.nextMsg() != 0){

        getsize.getInt() => width;
        getsize.getInt() => height;

      <<<"size is", width, "by", height>>>;
}

//set prefix, brightness
xmit.startMsg("/sys/prefix", "s");
prefix => xmit.addString;

xmit.startMsg( prefix+"/grid/led/intensity", "i");
brightness => xmit.addInt;

<<<"brightness", brightness>>>;

clearDisplay();

recv.event( prefix+"/grid/key", "iii") @=> OscEvent oe;

recv.event(prefix+"/grid/key", ",iii") @=> OscEvent press;

/// INITIAL MIDI CHANNELS
1 => grid[0].channel;
2 => grid[1].channel;
3 => grid[2].channel;
4 => grid[3].channel;
5 => grid[4].channel;
6 => grid[5].channel;
7 => grid[6].channel;
8 => grid[7].channel;
9 => grid[8].channel;
10 => grid[9].channel;
11 => grid[10].channel;
12 => grid[11].channel;

///INITIAL LFOS FOR EACH CHANNEL
0 => grid[0].lfo;
1 => grid[1].lfo;
2 => grid[2].lfo;
3 => grid[3].lfo;
4 => grid[4].lfo;
5 => grid[5].lfo;
6 => grid[6].lfo;
7 => grid[7].lfo;
0 => grid[8].lfo;
1 => grid[9].lfo;
2 => grid[10].lfo;
3 => grid[11].lfo;

/// INITIAL LAYER SCALES
1 => grid[0].scale;
1 => grid[1].scale;
1 => grid[2].scale;
1 => grid[3].scale;
9 => grid[9].scale;     // MIDI Drums
7 => grid[6].scale;     // Ableton Drums
7 => grid[7].scale;     // Ableton Drums

/// INITIAL LAYER SWING LEVELS
//1 => grid[0].swing;

200::ms => dur press_thresh;

int gesture_flag, overlay_flag, gesture_x, gesture_y;
int mute_bitwise;
time overlay_mode_clear_time;
int pushMatrix[maxx][maxy];
int overlayMatrix[maxx][maxy];
int matrix_buffer[maxx][maxy];

time timeMatrix[maxx][maxy];

1023 => int pulse;

///Set velocity lookup table
int velocity_table[];

if (maxy == 16){            // 256
    [0, 7, 15, 23, 31, 47, 55, 63, 71, 79, 87, 95, 103, 111, 119, 127] @=> velocity_table;
} else if (maxy == 8){      // 64 & 128
    [0, 15, 31, 55, 71, 87, 103, 127] @=> velocity_table;
}

int volume_table[];

if (maxx == 16){            // 256 & 128
    [0, 7, 15, 23, 31, 47, 55, 63, 71, 79, 87, 95, 103, 111, 119, 127] @=> volume_table;
} else if (maxx == 8){      // 64
    [0, 15, 31, 55, 71, 87, 103, 127] @=> volume_table;
}

int cc_table[];

if (maxy == 16){            // 256
    [0, 7, 15, 23, 31, 47, 55, 63, 71, 79, 87, 95, 103, 111, 119, 127] @=> cc_table;
} else if (maxy == 8){      // 64 & 128
    [0, 15, 31, 55, 71, 87, 103, 127] @=> cc_table;
}

// TRANSMIT DEFAULT MIDI CHANNEL VOLUME
for (0 => int i; i<16; i++){

	midiChannel[i].volume => int y;
	midiController(i, 7, volume_table[y]);

}

// Octomod setup for voltage control
// Configuration for sending voltages from LFOs to Greg Surges' Octomod

10 => int goct_lat;	// Update latency

// Octomod - Send
"localhost" => string omhost;
9999 => int omhostport;				/// CHANGE FOR YOUR SETUP: Octomod OSC Port
"/dac" => string omprefix;
OscSend oemit;

if (enable_octomod){
	oemit.setHost(omhost, omhostport);
	spork ~octoModulate();
}

clearDisplay();

bpm/2   => float tick;
minute/tick => dur beat;

spork ~pulseMidiClock(); // MIDI CLOCK NOT WORKING
midiStartClock();

spork ~keyPress();

12 => int max_sequences;

for (0 => int i; i< max_sequences; i++){

spork ~stepSequence(i);

}

while ( true ) {

1::second => now;

}

fun void stepSequence(int matrix) {

0 => int i;
0 => int step_seq;
0 => int mute;
dur tick_time;

writeConfig();
readConfig();

while (true){


    // BRIEF EXPLANATION:
    // Two variables control playback. step_seq counts out the number of steps
    // in a pattern so that the speed can be set at the correct point when the
    // playback mode is 'random' or 'reverse'. 'i' follows the plackback head
    // through the matrix note buffer, and depends on the direction of playback

	if (!(step_seq < grid[matrix].steps-1)) // If we're at the beginning of a pattern
		grid[matrix].mute => mute;	// set whether matrix is muted when
						// it starts

    if (grid[matrix].direction == 1){           // Playback direction = FORWARDS

        if (i<grid[matrix].steps-1){
            i++;
        } else {
            0 => i;
        }

        if (step_seq < grid[matrix].steps-1) {
            step_seq++;
        } else {
            beat/grid[matrix].time_sig => tick_time;
            grid[matrix].time_sig => grid[matrix].time_sync;
            0 => step_seq;
        }

    } else if (grid[matrix].direction == 2) {           // Playback direction = RANDOM

        Std.rand2(0,grid[matrix].steps-1)=>i;

        if (step_seq < grid[matrix].steps-1) {
            step_seq++;
        } else {
            beat/grid[matrix].time_sig => tick_time;
            grid[matrix].time_sig => grid[matrix].time_sync;
            0 => step_seq;
        }

    } else if (grid[matrix].direction == 0) {            // Playback direction = REVERSE
        if (i > 0){
            i--;
        } else {
            grid[matrix].steps-1 => i;
        }

        if (step_seq > 0) {
            step_seq--;
        } else {
            beat/grid[matrix].time_sig => tick_time;
            grid[matrix].time_sig => grid[matrix].time_sync;
            grid[matrix].steps-1 => step_seq;
        }

    }

	// Decide whether the probability setting
	// and the 'skip' step flag means we skip this step

	if ((( maxy == grid[matrix].prb_steps[i] ) ||				// Probability
	   ( Std.rand2(1, maxy) <= grid[matrix].prb_steps[i])) &&
	   (!grid[matrix].skip_steps[i])) {							// Skip steps

    // Play the notes for current step
	if (!mute)
    	playStep(matrix, i);

    // Flash the LEDs - Step cursor
    if (current_matrix == matrix) {

		if (overlay_flag){
			if (overlayMatrix[i][0]){
				ledSet(i, 0, 0);
			} else {
				ledSet(i, 0, 1);
			}
		} else if (grid[current_matrix].matrix[i][0]){
	        ledSet(i, 0, 0);
	    } else {
	        ledSet(i, 0, 1);
	    }

		tickTock(matrix, tick_time);

		if (overlay_flag){
			if (overlayMatrix[i][0]){
				ledSet(i, 0, 1);
			} else {
				ledSet(i, 0, 0);
			}
		} else if (grid[current_matrix].matrix[i][0]){
	        ledSet(i, 0, 1);
	    } else {
	        ledSet(i, 0, 0);
	    }

    } else {
		tickTock(matrix, tick_time);
    }

	}


} /// END WHILE TRUE

}

// Tick forward the time. If Swing is set, then
// make sure to skip forward/backward in time
// twice to equalise the effect
fun void tickTock(int matrix, dur tick_time){

	if (grid[matrix].swing){
		if (grid[matrix].swing_state){
			/// Here second
			tick_time - grid[matrix].tick_time => now;
			if (matrix==0 && enable_clockpulse==1)
				spork ~clock_pulse();
			grid[matrix].swing_state--;

		} else {
			/// Here first
			(tick_time/maxx)*grid[matrix].swing => grid[matrix].tick_time;
			tick_time + grid[matrix].tick_time => now;
			if (matrix==0 && enable_clockpulse==1)
				spork ~clock_pulse();
			grid[matrix].swing_state++;
		}
	} else if (grid[matrix].swing_state) {

		tick_time - grid[matrix].tick_time => now;
		if (matrix==0 && enable_clockpulse==1)
			spork ~clock_pulse();
		grid[matrix].swing_state--;

	} else {

		tick_time => now;
		if (matrix==0 && enable_clockpulse==1)
			spork ~clock_pulse();
	}

}

fun void outputMatrix(int matrix) {

<<< grid[matrix].matrix[0][0],grid[matrix].matrix[1][0],grid[matrix].matrix[2][0],grid[matrix].matrix[3][0],grid[matrix].matrix[4][0],grid[matrix].matrix[5][0],grid[matrix].matrix[6][0],grid[matrix].matrix[7][0],grid[matrix].matrix[8][0],grid[matrix].matrix[9][0],grid[matrix].matrix[10][0],grid[matrix].matrix[11][0],grid[matrix].matrix[12][0],grid[matrix].matrix[13][0],grid[matrix].matrix[14][0],grid[matrix].matrix[15][0] >>>;
<<< grid[matrix].matrix[0][1],grid[matrix].matrix[1][1],grid[matrix].matrix[2][1],grid[matrix].matrix[3][1],grid[matrix].matrix[4][1],grid[matrix].matrix[5][1],grid[matrix].matrix[6][1],grid[matrix].matrix[7][1],grid[matrix].matrix[8][1],grid[matrix].matrix[9][1],grid[matrix].matrix[10][1],grid[matrix].matrix[11][1],grid[matrix].matrix[12][1],grid[matrix].matrix[13][1],grid[matrix].matrix[14][1],grid[matrix].matrix[15][1] >>>;
<<< grid[matrix].matrix[0][2],grid[matrix].matrix[1][2],grid[matrix].matrix[2][2],grid[matrix].matrix[3][2],grid[matrix].matrix[4][2],grid[matrix].matrix[5][2],grid[matrix].matrix[6][2],grid[matrix].matrix[7][2],grid[matrix].matrix[8][2],grid[matrix].matrix[9][2],grid[matrix].matrix[10][2],grid[matrix].matrix[11][2],grid[matrix].matrix[12][2],grid[matrix].matrix[13][2],grid[matrix].matrix[14][2],grid[matrix].matrix[15][2] >>>;
<<< grid[matrix].matrix[0][3],grid[matrix].matrix[1][3],grid[matrix].matrix[2][3],grid[matrix].matrix[3][3],grid[matrix].matrix[4][3],grid[matrix].matrix[5][3],grid[matrix].matrix[6][3],grid[matrix].matrix[7][3],grid[matrix].matrix[8][3],grid[matrix].matrix[9][3],grid[matrix].matrix[10][3],grid[matrix].matrix[11][3],grid[matrix].matrix[12][3],grid[matrix].matrix[13][3],grid[matrix].matrix[14][3],grid[matrix].matrix[15][3] >>>;
<<< grid[matrix].matrix[0][4],grid[matrix].matrix[1][4],grid[matrix].matrix[2][4],grid[matrix].matrix[3][4],grid[matrix].matrix[4][4],grid[matrix].matrix[5][4],grid[matrix].matrix[6][4],grid[matrix].matrix[7][4],grid[matrix].matrix[8][4],grid[matrix].matrix[9][4],grid[matrix].matrix[10][4],grid[matrix].matrix[11][4],grid[matrix].matrix[12][4],grid[matrix].matrix[13][4],grid[matrix].matrix[14][4],grid[matrix].matrix[15][4] >>>;
<<< grid[matrix].matrix[0][5],grid[matrix].matrix[1][5],grid[matrix].matrix[2][5],grid[matrix].matrix[3][5],grid[matrix].matrix[4][5],grid[matrix].matrix[5][5],grid[matrix].matrix[6][5],grid[matrix].matrix[7][5],grid[matrix].matrix[8][5],grid[matrix].matrix[9][5],grid[matrix].matrix[10][5],grid[matrix].matrix[11][5],grid[matrix].matrix[12][5],grid[matrix].matrix[13][5],grid[matrix].matrix[14][5],grid[matrix].matrix[15][5] >>>;
<<< grid[matrix].matrix[0][6],grid[matrix].matrix[1][6],grid[matrix].matrix[2][6],grid[matrix].matrix[3][6],grid[matrix].matrix[4][6],grid[matrix].matrix[5][6],grid[matrix].matrix[6][6],grid[matrix].matrix[7][6],grid[matrix].matrix[8][6],grid[matrix].matrix[9][6],grid[matrix].matrix[10][6],grid[matrix].matrix[11][6],grid[matrix].matrix[12][6],grid[matrix].matrix[13][6],grid[matrix].matrix[14][6],grid[matrix].matrix[15][6] >>>;
<<< grid[matrix].matrix[0][7],grid[matrix].matrix[1][7],grid[matrix].matrix[2][7],grid[matrix].matrix[3][7],grid[matrix].matrix[4][7],grid[matrix].matrix[5][7],grid[matrix].matrix[6][7],grid[matrix].matrix[7][7],grid[matrix].matrix[8][7],grid[matrix].matrix[9][7],grid[matrix].matrix[10][7],grid[matrix].matrix[11][7],grid[matrix].matrix[12][7],grid[matrix].matrix[13][7],grid[matrix].matrix[14][7],grid[matrix].matrix[15][7] >>>;

}

fun void keyPress() {

  int x, y, state;
  time timeMatrix[maxx][maxy];

  while (true){

    press => now;

    while (press.nextMsg()){

        press.getInt() => x;
        press.getInt() => y;
        press.getInt() => state;

/// GESTURE ROUTINE. Short press lights the LED. Long press starts a gesture.
/// When key is pressed down, flag the key and timestamp.
/// interpretPress function will spork to wait to see if press is longer than simple press.

        if ((x < maxx) && (y < maxy)){  // Quick sanity check for smaller instances
            if (gesture_flag){
                interpretGesture(x, y, state);
            } else if (state) {
                1 => pushMatrix[x][y];
                now => timeMatrix[x][y];
                spork ~interpretPress(x, y);
            } else if ((now - timeMatrix[x][y]) < press_thresh){
                0 => pushMatrix[x][y];
                updateMatrix(current_matrix, x,y,short_note);
            }
        }
    }
  }
}

fun void interpretPress(int x, int y){

    press_thresh => now;

    if (pushMatrix[x][y]){

        1 => gesture_flag;
        x => gesture_x;
        y => gesture_y;

		/// if gesture is an overlay
		if ((y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
			overlayGesturePage1();
		} else if ((y == key_glfo[1]) && (x == key_glfo[0])){
			overlayGesturePage2();
		} else if ((y == key_volume[1]) && (x == key_volume[0])){
			overlayGesturePage4();
		} else if ((y == key_lfo[1]) && (x == key_lfo[0])){
			overlayGesturePage5();
		} else if ((y == key_prb[1]) && (x == key_prb[0])){
			overlayGesturePage6();
		} else if ((y == key_cc1[1]) && (x == key_cc1[0])){
			overlayGesturePage7();
		} else if ((y == key_cc2[1]) && (x == key_cc2[0])){
			overlayGesturePage8();
		}
    }

    0 => pushMatrix[x][y];

}

fun void overlayGesturePage1(){			// Overlay: general

	1 => overlay_flag;

	if (maxx == 16){

		grid[current_matrix].channel => int mchannel;
		clearDisplay();
		overlayRowOne(0,current_matrix);
		//overlayRow(key_step_size[1],grid[current_matrix].steps);
		overlaySkipSteps(key_step_size[1],current_matrix);
		overlayRow(key_time[1],grid[current_matrix].time_sig_table_pos);
		overlayRow(key_volume[1],midiChannel[mchannel].volume);
		overlayRow(key_transpose[1],grid[current_matrix].transpose_table_pos);
		overlayRow(key_scale[1],grid[current_matrix].scale);
		//overlayRow(key_channel[1],grid[current_matrix].channel);
		overlayRow(key_swing[1],grid[current_matrix].swing+1);
		overlayMutedLayers(key_mute[1]);

	} else if (maxx == 8) {
						// Remember to take into account smaller monomes in table sizes
	}

}

fun void overlayGesturePage2(){			// Overlay: global LFO settings

	2 => overlay_flag;

	//clearDisplay();

	while (overlay_flag==2){
		lfoDisplayEdit();
		20::ms => now;
	}
}

fun void overlayGesturePage4(){			// Overlay: volume

	4 => overlay_flag;

	for (0=> int i; i<maxx; i++)
		overlayColumn(i, grid[current_matrix].velocity_steps[i]);

}

fun void overlayGesturePage5(){			// Overlay: per-step LFO modulation amount

	5 => overlay_flag;

	while (overlay_flag==5){

	//spork ~lfoDisplayUpdate();
	lfoDisplayUpdate();

	20::ms => now;

	}
}

fun void overlayGesturePage6(){			// Overlay: probability layer

	6 => overlay_flag;

	for (0=> int i; i<maxx; i++)
		overlayColumn(i, grid[current_matrix].prb_steps[i]);

}

fun void overlayGesturePage7(){			// Overlay: cc1

	7 => overlay_flag;

	for (0=> int i; i<maxx; i++)
		overlayColumn(i, grid[current_matrix].cc1_steps[i]);

}

fun void overlayGesturePage8(){			// Overlay: cc2

	8 => overlay_flag;

	for (0=> int i; i<maxx; i++)
		overlayColumn(i, grid[current_matrix].cc2_steps[i]);

}

fun void interpretGesture(int x, int y, int state){		// Key control while in Overlay mode

	/// Deal with overlay gestures first
	if (overlay_flag == 1){
		overlayMode1(x,y,state);			// Global options
	} else if (overlay_flag == 2){
		overlayMode2(x,y,state);			// Global LFO
	} else if (overlay_flag == 4){
		overlayMode4(x,y,state);			// Step velocity
	} else if (overlay_flag == 5){
		overlayMode5(x,y,state);			// Step lfo modulation
	} else if (overlay_flag == 6){
		overlayMode6(x,y,state);			// Step probability
	} else if (overlay_flag == 7){
		overlayMode7(x,y,state);			// Step cc1
	} else if (overlay_flag == 8){
		overlayMode8(x,y,state);			// step cc2
	} else {
		standardGestureMode(x,y,state);
		0 => gesture_flag;
	}
}

fun void overlayMode1(int x, int y, int state){

	if (state==0)
	if ((y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){

			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;

	} else if (y == key_step_size[1])		/// ALTER STEP SIZE
		stepResize(current_matrix, x);

	else if (y == key_time[1])    			/// ALTER TIME SIGNATURE
    	layerTime(current_matrix, x);

	else if (y == key_volume[1])			/// ALTER LAYER VOLUME
    	layerVolume(current_matrix, x);

	else if (y == key_transpose[1])		  	/// ALTER LAYER TRANPOSITION
    	layerTranspose(current_matrix, x);

	else if (y == key_scale[1])			 	/// ALTER LAYER SCALE
    	layerScale(current_matrix, x);

//	else if (y == key_channel[1])	    	/// ALTER LAYER CHANNEL
//    	layerChannel(current_matrix, x);

	else if (y == key_swing[1])	    	/// ALTER LAYER SWING
   		layerSwing(current_matrix, x);

	else if (y == key_mute[1])	    		/// ALTER LAYER MUTE
    	layerMute(current_matrix, x);

	else if ((y == key_layer_0[1]) && (x == key_layer_0[0]))
		switchLayer(0);

	else if ((y == key_layer_1[1]) && (x == key_layer_1[0]))
		switchLayer(1);

	else if ((y == key_layer_2[1]) && (x == key_layer_2[0]))
		switchLayer(2);

	else if ((y == key_layer_3[1]) && (x == key_layer_3[0]))
		switchLayer(3);

	else if ((y == key_layer_4[1]) && (x == key_layer_4[0]))
		switchLayer(4);

	else if ((y == key_layer_5[1]) && (x == key_layer_5[0]))
		switchLayer(5);

	else if ((y == key_layer_6[1]) && (x == key_layer_6[0]))
		switchLayer(6);

	else if ((y == key_layer_7[1]) && (x == key_layer_7[0]))
		switchLayer(7);

	else if ((y == key_layer_8[1]) && (x == key_layer_8[0]))
		switchLayer(8);

	else if ((y == key_layer_9[1]) && (x == key_layer_9[0]))
		switchLayer(9);

	else if ((y == key_layer_10[1]) && (x == key_layer_10[0]))
		switchLayer(10);

	else if ((y == key_layer_11[1]) && (x == key_layer_11[0]))
		switchLayer(11);

	else if ((y == key_backwards[1]) && (x == key_backwards[0]))
		0 => grid[current_matrix].direction; /// RUN BACKWARDS

	else if ((y == key_forwards[1]) && (x == key_forwards[0]))
		1 => grid[current_matrix].direction; /// RUN FORWARDS

	else if ((y == key_random[1]) && (x == key_random[0]))
		2 => grid[current_matrix].direction; /// RANDOM SEQUENCE

}

fun void overlayMode2(int x, int y, int state){

	if (state==0)
	if ((y == key_glfo[1]) && (x == key_glfo[0])){

			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;

	} else if ((y == key_layer_0[1]) && (x == key_layer_0[0]))
			0 => grid[current_matrix].lfo; /// Switch LFO used by current grid

	else if ((y == key_layer_1[1]) && (x == key_layer_1[0]))
			1 => grid[current_matrix].lfo;

	else if ((y == key_layer_2[1]) && (x == key_layer_2[0]))
			2 => grid[current_matrix].lfo;

	else if ((y == key_layer_3[1]) && (x == key_layer_3[0]))
			3 => grid[current_matrix].lfo;

	else if ((y == key_layer_4[1]) && (x == key_layer_4[0]))
			4 => grid[current_matrix].lfo;

	else if ((y == key_layer_5[1]) && (x == key_layer_5[0]))
			5 => grid[current_matrix].lfo;

	else if ((y == key_layer_6[1]) && (x == key_layer_6[0]))
			6 => grid[current_matrix].lfo;

	else if ((y == key_layer_7[1]) && (x == key_layer_7[0]))
			7 => grid[current_matrix].lfo;

	else if ((y == key_layer_8[1]) && (x == key_layer_8[0]))
			8 => grid[current_matrix].lfo;

	else if (y == key_mute[1])		/// ALTER LFO FREQUENCY
		  	(((x+1)*2)/5.0)*(60.0/bpm) => lfo[current_matrix].frequency;

	else if (y == key_swing[1])		/// ALTER LFO TYPE
			x => lfo[current_matrix].type;

}

fun void overlayMode4(int x, int y, int state){

	if ((state) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		1 => pushMatrix[x][y];
		now => overlay_mode_clear_time;
	} else if ((state==0) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		if ((now - press_thresh) > overlay_mode_clear_time){
			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;
		} else{
			maxy - y => grid[current_matrix].velocity_steps[x];
			overlayColumn(x, grid[current_matrix].velocity_steps[x]);
		}
	} else if (state==1) {

		maxy - y => grid[current_matrix].velocity_steps[x];
		overlayColumn(x, grid[current_matrix].velocity_steps[x]);
	}
}

// Overlay control for LFO modulation layer
fun void overlayMode5(int x, int y, int state){

	if ((state) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		1 => pushMatrix[x][y];
		now => overlay_mode_clear_time;
	} else if ((state==0) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		if ((now - press_thresh) > overlay_mode_clear_time){
			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;
		} else{
			maxy - y => grid[current_matrix].lfo_steps[x];
		}
	} else if (state==1) {
		maxy - y => grid[current_matrix].lfo_steps[x];
	}

}

// Overlay control for probability layer
fun void overlayMode6(int x, int y, int state){

	if ((state) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		1 => pushMatrix[x][y];
		now => overlay_mode_clear_time;
	} else if ((state==0) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		if ((now - press_thresh) > overlay_mode_clear_time){
			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;
		} else{
			maxy - y => grid[current_matrix].prb_steps[x];
			overlayColumn(x, grid[current_matrix].prb_steps[x]);
			}
	} else if (state==1) {
		maxy - y => grid[current_matrix].prb_steps[x];
		overlayColumn(x, grid[current_matrix].prb_steps[x]);
	}
}

// Overlay control for cc1
fun void overlayMode7(int x, int y, int state){

	if ((state) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		1 => pushMatrix[x][y];
		now => overlay_mode_clear_time;
	} else if ((state==0) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		if ((now - press_thresh) > overlay_mode_clear_time){
			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;
		} else{
			maxy - y => grid[current_matrix].cc1_steps[x];
			overlayColumn(x, grid[current_matrix].cc1_steps[x]);
			}
	} else if (state==1) {

		maxy - y => grid[current_matrix].cc1_steps[x];
		overlayColumn(x, grid[current_matrix].cc1_steps[x]);
	}
}

// Overlay control for cc2
fun void overlayMode8(int x, int y, int state){

	if ((state) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		1 => pushMatrix[x][y];
		now => overlay_mode_clear_time;
	} else if ((state==0) && (y == key_clear_pattern[1]) && (x == key_clear_pattern[0])){
		if ((now - press_thresh) > overlay_mode_clear_time){
			clearDisplay();
			drawDisplay();
			0 => overlay_flag;
			0 => gesture_flag;
		} else{
			maxy - y => grid[current_matrix].cc2_steps[x];
			overlayColumn(x, grid[current_matrix].cc2_steps[x]);
		}
	} else if (state==1) {

		maxy - y => grid[current_matrix].cc2_steps[x];
		overlayColumn(x, grid[current_matrix].cc2_steps[x]);
	}
}

fun void standardGestureMode(int x, int y, int state){

	  	/// LAYER 0
		if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_0[1]) && (x == key_layer_0[0])))
	        switchLayer(0);

	    /// LAYER 1
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_1[1]) && (x == key_layer_1[0])))
	        switchLayer(1);

	    /// LAYER 2
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_2[1]) && (x == key_layer_2[0])))
	        switchLayer(2);

	    /// LAYER 3
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_3[1]) && (x == key_layer_3[0])))
	        switchLayer(3);

	    /// LAYER 4
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_0[1]) && (x == key_layer_4[0])))
	        switchLayer(4);

	    /// LAYER 5
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_1[1]) && (x == key_layer_5[0])))
	        switchLayer(5);

	    /// LAYER 6
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_2[1]) && (x == key_layer_6[0])))
	        switchLayer(6);

	    /// LAYER 7
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_3[1]) && (x == key_layer_7[0])))
	        switchLayer(7);

	    /// LAYER 8
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_0[1]) && (x == key_layer_8[0])))
	        switchLayer(8);

	    /// LAYER 9
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_1[1]) && (x == key_layer_9[0])))
	        switchLayer(9);

	    /// LAYER 10
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_2[1]) && (x == key_layer_10[0])))
	        switchLayer(10);

	    /// LAYER 11
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_layer_3[1]) && (x == key_layer_11[0])))
	        switchLayer(11);

	    /// LONG NOTE
	    else if ((y == gesture_y) && (x > gesture_x))     // Same row, and a column to the right of the original
	        addLongNote(current_matrix, gesture_x, gesture_y, x);

		else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_backwards[1]) && (x == key_backwards[0])))
			copyLayer();
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_forwards[1]) && (x == key_forwards[0])))
			cutLayer();
	    else if (((y == gesture_y) && (x == gesture_x)) && ((y == key_random[1]) && (x == key_random[0])))
			pasteLayer();


}


fun void lfoDisplayEdit(){

	0 => int binary_send;
	0.001953125 => float step_multiplier; // 0.001953125 * 512 = 1

	for (0=> int x; x<maxx; x++){
		Math.pow(2,(lfo[grid[current_matrix].lfo].value_table[x]/(1024/maxy))) $ int +=> binary_send;
		1 -=> binary_send;			// Reverse display
		0xff ^=> binary_send; 		// so that waveform appears correctly
		columnSet(x, binary_send);
		0 => binary_send;
	}

}

fun void lfoDisplayUpdate(){

	0 => int binary_send;
	0.001953125 => float step_multiplier; // 0.001953125 * 512 = 1

	for (0=> int x; x<maxx; x++){
		for (0=> int y; y<maxy; y++){
			if (grid[current_matrix].matrix[x][y]){
				if (lfo[grid[current_matrix].lfo].value_table[x]>512){		// If LFO is positive
					Math.pow(2,(y+grid[current_matrix].lfo_value[x])) $ int +=> binary_send;
				} else {					// If LFO is negative
					Math.pow(2,(y-grid[current_matrix].lfo_value[x])) $ int +=> binary_send;
				}
			}
		}
		columnSet(x, binary_send);
		0 => binary_send;
	}
}

fun void lfo_backgroundUpdate(){

	0.001953125 => float step_multiplier; // 0.001953125 * 512 = 1

	while (true){

		for (0=> int x; x<maxx; x++){
			for (0=> int y; y<maxy; y++){

				for (0=> int l; l<layers; l++){

					for (0=> int o; o<maxlfo; o++){

						if (grid[l].matrix[x][y]){

							if (lfo[o].value_table[x]>512){		// If LFO is positive
								lfo[o].value_table[x] - 512 => int lfo_value;
								lfo_value * (step_multiplier*grid[l].lfo_steps[x]) => float multiplier;
								multiplier $ int => int final_val;
								final_val => grid[l].lfo_value[x];
							} else {					// If LFO is negative
								lfo[o].value_table[x] - 511 => int lfo_value;
								lfo_value * -1 => lfo_value;
								lfo_value * (step_multiplier*grid[l].lfo_steps[x]) => float multiplier;
								multiplier $ int => int final_val;
								final_val => grid[l].lfo_value[x];
							}
						}

					}
				}
			}
		}

		20::ms => now;
	}
}


fun void layerVolume(int matrix, int x){

	grid[matrix].channel => int mchannel;

	x+1 => midiChannel[mchannel].volume;

	midiController(mchannel, 7, volume_table[x]);

	if (overlay_flag)
		overlayRow(key_volume[1], midiChannel[mchannel].volume);

}

fun void layerTranspose(int matrix, int x){

	x+1 => grid[matrix].transpose_table_pos;

	if (overlay_flag)
		overlayRow(key_transpose[1],grid[matrix].transpose_table_pos);

    /// ***MONOME TYPE SPECIFIC***
    if (maxx == 16){            // 128 & 256
        [-7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 0] @=> int transpose_table[];
        transpose_table[x] => grid[matrix].transpose;
    } else if (maxx == 8){      // 64
        [-7, -5, -3, -1, 0, 2, 4, 6] @=> int transpose_table[];
        transpose_table[x] => grid[matrix].transpose;
    }
}

fun void layerScale(int matrix, int x){

    x+1 => grid[matrix].scale;

	if (overlay_flag)
		overlayRow(key_scale[1],grid[matrix].scale);

}

fun void layerChannel(int matrix, int x){

    x+1 => grid[matrix].channel;

	midiChannel[x+1].volume => int volume;
	midiController(grid[matrix].channel, 7, volume_table[volume]);

	if (overlay_flag){
		overlayRow(key_channel[1],grid[matrix].channel);
		overlayRow(key_volume[1], midiChannel[x+1].volume);
	}
}

fun void layerSwing(int matrix, int x){

	grid[matrix].swing => grid[matrix].swing_sync;
    x => grid[matrix].swing;

	if (overlay_flag){
		overlayRow(key_swing[1],grid[matrix].swing+1);
	}
}

fun void layerMute(int current_matrix, int x){

		if (x < max_sequences){
			if (grid[x].mute)
				0 => grid[x].mute;
			else
				1 => grid[x].mute;

			overlayMutedLayers(key_mute[1]);
		}
}

fun void stepResize(int matrix, int x){

		if (grid[matrix].skip_steps[x])
			0 => grid[matrix].skip_steps[x];
		else
			1 => grid[matrix].skip_steps[x];

		overlaySkipSteps(key_step_size[1], matrix);
}

fun void stepResize_old(int matrix, int x){

    x+1 => grid[matrix].steps;

	if (overlay_flag)
		overlayRow(key_step_size[1],grid[current_matrix].steps);

}

fun void layerTime(int matrix, int x){

	x+1 => grid[matrix].time_sig_table_pos;

	if (overlay_flag)
		overlayRow(key_time[1],grid[current_matrix].time_sig_table_pos);

    [1, 2, 4, 8, 16, 32, 64, 128, 1, 1, 1, 1, 1, 1, 1, 1] @=> int time_sig_table[];

    grid[matrix].time_sig => grid[matrix].time_sync;
    time_sig_table[x] => grid[matrix].time_sig;

}

fun void switchLayer(int matrix){

    matrix => current_matrix;

	if 	(overlay_flag == 1){
		<<< "Switching layer :", matrix >>>;
		overlayGesturePage1();
	} else {
		<<< "Switching layer :", matrix >>>;
		drawDisplay();
	}
}

fun void copyLayer(){

	<<< "Copied Layer :", current_matrix >>>;

	for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            grid[current_matrix].matrix[x][y] => matrix_buffer[x][y];

}

fun void cutLayer(){

	<<< "Cut Layer :", current_matrix >>>;

	for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            grid[current_matrix].matrix[x][y] => matrix_buffer[x][y];

    clearPattern(current_matrix);
	drawDisplay();

}

fun void pasteLayer(){

	<<< "Pasted Layer :", current_matrix >>>;

    clearPattern(current_matrix);

	for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            matrix_buffer[x][y] => grid[current_matrix].matrix[x][y];

	drawDisplay();

}

fun void addLongNote(int matrix, int x1, int y1, int x2){

    for (x1=> int i; i<=x2; i++){
        updateMatrix(matrix, i,y1,long_note);

    }

}

fun void updateMatrix(int matrix, int x, int y, int notetype){

    if (grid[matrix].matrix[x][y]){
        0 => grid[matrix].matrix[x][y];
	    ledSet(x, y, 0);
    } else {
	    notetype => grid[matrix].matrix[x][y];
	    ledSet(x, y, 1);
    }
}

fun int returnVelocity(int matrix, int step){

	grid[matrix].velocity_steps[step] => int position;

	return velocity_table[position-1];

}

fun int returnCC1(int matrix, int step){

	grid[matrix].cc1_steps[step] => int position;

	return cc_table[position-1];

}

fun int returnCC2(int matrix, int step){

	grid[matrix].cc2_steps[step] => int position;

	return cc_table[position-1];

}

fun void playStep(int matrix, int step) {

    int note_number;

    for ( 0=> int i; i<maxy; i++){

        if (grid[matrix].matrix[step][i]==short_note){

            ///Scale and transpose function
            64-i => note_number;
            mscale.table[grid[matrix].scale][note_number] => note_number;
            grid[matrix].transpose * grid[matrix].transpose_step + note_number => note_number;

			/// LFO modulation onto note number
			if (lfo[grid[matrix].lfo].value_table[step]>512){
				grid[matrix].lfo_value[step] -=> note_number;
			} else {
				grid[matrix].lfo_value[step] +=> note_number;
			}

			/// Send MIDI Controller date for step
			spork ~midiController(grid[matrix].channel, grid[matrix].cc1_value, returnCC1(matrix, step));
			/// Send Channel Pressure for step
			spork ~midiChPressure(grid[matrix].channel, returnCC2(matrix, step));
			//spork ~midiController(grid[matrix].channel, grid[matrix].cc2_value, returnCC2(matrix, step));


			if (enable_layerpulse == 1 && matrix == pulse_layer){
				spork ~clock_pulse();
			} else
				spork ~midiNote(grid[matrix].channel, note_number, returnVelocity(matrix, step), 1, grid[matrix].time_sync);

            spork ~toggleLED(matrix, step, i);

        } else if ((grid[matrix].matrix[step][i]==long_note) &&
                   (step == 0)) {
            step => int x;
            while ((grid[matrix].matrix[x][i]==long_note) && (x < maxx-1))
                x++;
            ///Scale and transpose function
            64-i => note_number;
            mscale.table[grid[matrix].scale][note_number] => note_number;
            grid[matrix].transpose * grid[matrix].transpose_step + note_number => note_number;

			/// LFO modulation onto note number
			if (lfo[grid[matrix].lfo].value_table[step]>512){
				grid[matrix].lfo_value[step] -=> note_number;
			} else {
				grid[matrix].lfo_value[step] +=> note_number;
			}

			/// Send MIDI Controller date for step
			spork ~midiController(grid[matrix].channel, grid[matrix].cc1_value, returnCC1(matrix, step));
			/// Send Channel Pressure for step
			spork ~midiChPressure(grid[matrix].channel, returnCC2(matrix, step));
			//spork ~midiController(grid[matrix].channel, grid[matrix].cc2_value, returnCC2(matrix, step));

			if (enable_layerpulse == 1 && matrix == pulse_layer){
				spork ~clock_pulse();
			} else
				spork ~midiNote(grid[matrix].channel, note_number, returnVelocity(matrix, step), 1, grid[matrix].time_sync);

            spork ~toggleLED(matrix, step, i);

        } else if ((grid[matrix].matrix[step][i]==long_note) &&
                   (grid[matrix].matrix[step-1][i]!=long_note)){
            step => int x;
            while ((grid[matrix].matrix[x][i]==long_note) && (x < maxx-1))
                x++;

            ///Scale and transpose function
            64-i => note_number;
            mscale.table[grid[matrix].scale][note_number] => note_number;
            grid[matrix].transpose * grid[matrix].transpose_step + note_number => note_number;

			/// LFO modulation onto note number
			if (lfo[grid[matrix].lfo].value_table[step]>512){
				grid[matrix].lfo_value[step] -=> note_number;
			} else {
				grid[matrix].lfo_value[step] +=> note_number;
			}

			/// Send MIDI Controller date for step
			spork ~midiController(grid[matrix].channel, grid[matrix].cc1_value, returnCC1(matrix, step));
			/// Send Channel Pressure for step
			spork ~midiChPressure(grid[matrix].channel, returnCC2(matrix, step));
			//spork ~midiController(grid[matrix].channel, grid[matrix].cc2_value, returnCC2(matrix, step));

			if (enable_layerpulse == 1 && matrix == pulse_layer){
				spork ~clock_pulse();
			} else
				spork ~midiNote(grid[matrix].channel, note_number, returnVelocity(matrix, step), 1, grid[matrix].time_sync);

            spork ~toggleLED(matrix,  step, i);

        }
    }
}

fun void toggleLED(int matrix, int x, int y) {

    if (matrix == current_matrix) {
       if (grid[matrix].matrix[x][y]==short_note){
            flashButton(x,y);
        } else if ((grid[matrix].matrix[x][y]==long_note) &&
            (x==0)) {
            x => int xx;
            while ((grid[matrix].matrix[xx][y]==long_note)&&
               (xx < maxx-1)) {
                flashButton(xx,y);
                xx++;
            }
        } else if ((grid[matrix].matrix[x][y]==long_note) &&
               (grid[matrix].matrix[x-1][y]!=long_note)) {
            x => int xx;
            while ((grid[matrix].matrix[xx][y]==long_note)&&
               (xx < maxx-1)) {
                flashButton(xx,y);
                xx++;
            }
        }
    /// Highlight notes on other layers
    } else if (!gesture_flag){
       if (grid[matrix].matrix[x][y]==short_note){
            flashButton(x,y);
        } else if ((grid[matrix].matrix[x][y]==long_note) &&
               (x==0)) {
            x => int xx;
            while ((grid[matrix].matrix[xx][y]==long_note)&&
               (xx < maxx-1)) {
                flashButton(xx,y);
                xx++;
            }
        } else if ((grid[matrix].matrix[x][y]==long_note) &&
               (grid[matrix].matrix[x-1][y]!=long_note)) {
            x => int xx;
            while ((grid[matrix].matrix[xx][y]==long_note)&&
               (xx < maxx-1)) {
                flashButton(xx,y);
                xx++;
            }
        }
    }
}

fun void flashButton(int x, int y){

	if (overlay_flag){
		if (overlayMatrix[x][y]){
			ledSet(x, y, 0);
	        50::ms => now;
	        if (overlayMatrix[x][y])  			// Stop LED being falsely turned off if
	            ledSet(x, y, 1);                // a button has been pressed during '=> now;'
		} else {
			ledSet(x, y, 1);
			50::ms => now;
	        if (!overlayMatrix[x][y])  			// Stop LED being falsely turned off if
	            ledSet(x, y, 0);                // a button has been pressed during '=> now;'
		}
	} else if (grid[current_matrix].matrix[x][y]){
        ledSet(x, y, 0);
        50::ms => now;
        if (grid[current_matrix].matrix[x][y])  // Stop LED being falsely turned off if
            ledSet(x, y, 1);                    // a button has been pressed during '=> now;'
    } else {
        ledSet(x, y, 1);
        50::ms => now;
        if (!grid[current_matrix].matrix[x][y]) // Stop LED being falsely turned off if
            ledSet(x, y, 0);                    // a button has been pressed during '=> now;'
    }
}

fun void xorLED(int x, int y){

	if (overlay_flag){
		if (overlayMatrix[x][y]){
			ledSet(x, y, 0);
		} else {
			ledSet(x, y, 1);
		}
	} else if (grid[current_matrix].matrix[x][y]){
        ledSet(x, y, 0);
    } else {
        ledSet(x, y, 1);
    }
}


fun void midiNote(int channel, int note, int velocity, int duration, int time_sig){

    float note_length;
    MidiMsg message;
    dur tick_time;

    /// NOTE ON
    0x9 => int command;

    ((command & 0xf) << 4) | ((channel - 1) & 0xf) => message.data1;
    command | channel => command;
    note & 0x7f => message.data2;
    velocity & 0x7f => message.data3;
    mout.send(message);

    (beat/time_sig) * duration => tick_time;
    tick_time => now;

    ///NOTE OFF
    ((0x8 & 0x0f) << 4) | ((channel - 1) & 0xf) => message.data1;
    mout.send(message);

}

fun void midiController(int channel, int controller, int value){

	MidiMsg message;

	// CONTROLLER DATA
	0xb => int command;

	((command & 0xf) << 4) | ((channel - 1) & 0xf) => message.data1;
	command | channel => command;
	controller | 0x00 => controller;
	controller & 0x7f => message.data2;
	value & 0x7f => message.data3;
	mout.send(message);

}

fun void midiChPressure(int channel, int value){

	MidiMsg message;

	// CONTROLLER DATA
	0xd => int command;
	int controller;

	((command & 0xf) << 4) | ((channel - 1) & 0xf) => message.data1;
	value & 0x7f => message.data2;
	mout.send(message);

}

fun void pulseMidiClock(){

	float midi_beat;

	// Crude one-time delay to get Meeq in time
	0.039::second => dur tick_new;
	tick_new => now;

	while (true){
		midiClock();

		(bpm*24)/60 => midi_beat;
		1/midi_beat => midi_beat;

		midi_beat::second => dur tick_new;

		tick_new => now;
	}

}

fun void midiStartClock(){

	MidiMsg message;
	0xfa => message.data1;
	0 => message.data2;
	0 => message.data3;

	mout.send(message);
}

fun void midiClock() {

	MidiMsg message;

	0xf8 => message.data1;
	0 => 	message.data2;
	0 => 	message.data3;

	mout.send(message);

}

fun void ledSet(int x,int y,int s){

    xmit.startMsg(prefix+"/grid/led/set", "iii");
    x => xmit.addInt;
    y => xmit.addInt;
    s => xmit.addInt;
}

fun void columnSet(int x,int s){
 
    xmit.startMsg(prefix+"/grid/led/col", "iii");
    x => xmit.addInt;
    0 => xmit.addInt;
    s => xmit.addInt;
}

fun void clearDisplay(){
    <<<"clearing display...","">>>;
    xmit.startMsg(prefix+"/grid/led/all", "i");
    0 => xmit.addInt;

}

fun void drawDisplay(){

    for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            ledSet(x, y, grid[current_matrix].matrix[x][y]);
}

fun void drawRow(int row, int value){

	for (0=> int x; x< maxx; x++)
		if (x<=value)
        	ledSet(x, row, 1);
		else
			ledSet(x, row, 0);
}

fun void overlayRow(int row, int value){

	for (0=> int x; x< maxx; x++){
		if (x<value){
        	ledSet(x, row, 1);
			1 => overlayMatrix[x][row];
		} else {
			ledSet(x, row, 0);
			0 => overlayMatrix[x][row];
		}
	}
}

fun void overlayColumn_old(int column, int value){

	(maxy - 1) - value => value;

	for (0=> int y; y < maxy; y++){
		if (y>value){
			ledSet(column, y, 1);
			1 => overlayMatrix[column][y];
		} else {
			ledSet(column, y, 0);
			0 => overlayMatrix[column][y];
		}
	}

}

fun void overlayColumn(int column, int value){

	0 => int binary_send;

	for (0=> int y; y < maxy; y++){
		if (y<value){
			Math.pow(2,(maxy-y)-1) $ int +=> binary_send;
			1 => overlayMatrix[column][(maxy-y)-1];
		} else {
			0 => overlayMatrix[column][(maxy-y)-1];
		}
	}

	columnSet(column, binary_send);

}

fun void overlayMutedLayers(int row){

	for (0 => int x; x< max_sequences; x++){

		if (grid[x].mute){
			ledSet(x, row, 0);
			0 => overlayMatrix[x][row];
		} else {
			ledSet(x, row, 1);
			1 => overlayMatrix[x][row];
		}
	}
}

fun void overlaySkipSteps(int row, int matrix){

	for (0 => int x; x< maxx; x++){

		if (grid[matrix].skip_steps[x]){
			ledSet(x, row, 0);
			0 => overlayMatrix[x][row];
		} else {
			ledSet(x, row, 1);
			1 => overlayMatrix[x][row];
		}
	}
}

fun void overlayRowOne(int row, int value){

	for (0=> int x; x< maxx; x++){
		if (x==value){
        	ledSet(x, row, 1);
			1 => overlayMatrix[x][row];
		} else {
			ledSet(x, row, 0);
			0 => overlayMatrix[x][row];
		}
	}
}

fun void everythingOn(){

    for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            ledSet(x, y, true);

}

fun void clearPattern(int matrix){

    for (0=> int x; x< maxx; x++)
        for (0=> int y; y< maxy; y++)
            0 => grid[matrix].matrix[x][y];

}

fun void writeConfig(){

	FileIO fout;

	fout.open( "meeq.xml", FileIO.WRITE );

	if( !fout.good() )
	{
	    cherr <= "can't open file for writing..." <= IO.newline();
	    me.exit();
	}

	fout <= "<meeq_config>" <= IO.newline();
	fout <= "<meeq_version> "; fout <= "1.91"; fout <= " </meeq_version>" <= IO.newline();

	for (0=> int x; x<layers; x++){
		fout <= "<layer>" <= IO.newline();
		fout <= "<direction> "; fout <= grid[x].direction; fout <= " </direction>" <= IO.newline();
		fout <= "<steps> "; fout <= grid[x].steps; fout <= " </steps>" <= IO.newline();
		fout <= "<channel_volume> "; fout <= grid[x].channel_volume; fout <= " </channel_volume>" <= IO.newline();
		fout <= "<time_sig> "; fout <= grid[x].time_sig; fout <= " </time_sig>" <= IO.newline();
		fout <= "<time_sig_table_pos> "; fout <= grid[x].time_sig_table_pos; fout <= " </time_sig_table_pos>" <= IO.newline();
		fout <= "<time_sync> "; fout <= grid[x].time_sync; fout <= " </time_sync>" <= IO.newline();
		fout <= "<channel> "; fout <= grid[x].channel; fout <= " </channel>" <= IO.newline();
		fout <= "<channel> "; fout <= grid[x].channel; fout <= " </channel>" <= IO.newline();
		fout <= "<scale> "; fout <= grid[x].scale; fout <= " </scale>" <= IO.newline();
		fout <= "<transpose> "; fout <= grid[x].transpose; fout <= " </transpose>" <= IO.newline();
		fout <= "<transpose_step> "; fout <= grid[x].transpose_step; fout <= " </transpose_step>" <= IO.newline();
		fout <= "<transpose_table_pos> "; fout <= grid[x].transpose_table_pos; fout <= " </transpose_table_pos>" <= IO.newline();
		fout <= "<mute> "; fout <= grid[x].mute; fout <= " </mute>" <= IO.newline();
		fout <= "<cc1_value> "; fout <= grid[x].cc1_value; fout <= " </cc1_value>" <= IO.newline();
		fout <= "<cc2_value> "; fout <= grid[x].cc2_value; fout <= " </cc2_value>" <= IO.newline();
		fout <= "<swing> "; fout <= grid[x].swing; fout <= " </swing>" <= IO.newline();
		fout <= "<swing_state> "; fout <= grid[x].swing_state; fout <= " </swing_state>" <= IO.newline();
		fout <= "<swing_sync> "; fout <= grid[x].swing_sync; fout <= " </swing_sync>" <= IO.newline();
		fout <= "<matrix> ";
		/// Left to right, top to bottom.
		for (0=> int i; i < maxy; i++)
			for (0=> int j; j < maxx; j++)
				fout <= grid[x].matrix[j][i];

		fout <= " </matrix>" <= IO.newline();
		fout <= "</layer>" <= IO.newline();
	}

	fout <= "</meeq_config>" <= IO.newline();

	fout.close();

}

fun void readConfig(){

	FileIO fin;

	fin.open( "meeq.xml", FileIO.READ );
	StringTokenizer tok;

	if( !fin.good() )
	{
	    cherr <= "can't open file for reading..." <= IO.newline();
	    me.exit();
	}

	string str;

	while( fin => str )
	{

	tok.set( str);
    chout <= tok.get(2) <= IO.newline();
    //chout <= tok.next() <= IO.newline();

	}
}

fun int lfo_generator(int which_lfo){

	1 => int direction;

	while (true){

		if (lfo[which_lfo].type==0){			/// Sine function

			for (0=> int i; i<900; i++){

				((Math.sin ((i/10)*3.14159265/180)) * 512 + 512-1) $ int => lfo[which_lfo].value;
				1/lfo[which_lfo].frequency => float div_click;
				div_click*0.27777777::ms => now;
			}

			for (900=> int i; i>0; i--){

				((Math.sin ((i/10)*3.14159265/180)) * 512 + 512-1) $ int => lfo[which_lfo].value;
				1/lfo[which_lfo].frequency => float div_click;
				div_click*0.27777777::ms => now;
			}

			for (0=> int i; i<900; i++){

				((Math.sin ((i/10)* -3.14159265/180)) * 512 + 512) $ int => lfo[which_lfo].value;
				1/lfo[which_lfo].frequency => float div_click;
				div_click*0.27777777::ms => now;
			}

			for (900=> int i; i>0; i--){

				((Math.sin ((i/10)* -3.14159265/180)) * 512 + 512) $ int => lfo[which_lfo].value;
				1/lfo[which_lfo].frequency => float div_click;
				div_click*0.27777777::ms => now;

			}
		} else if (lfo[which_lfo].type==1) {	/// Triangle function

				if (direction){

					if (lfo[which_lfo].value < 1023){
						lfo[which_lfo].value + 1 => lfo[which_lfo].value;
					} else {
						0 => direction;
					}
				} else {
					if (lfo[which_lfo].value > 0){
						lfo[which_lfo].value - 1 => lfo[which_lfo].value;
					} else {
						1 => direction;

					}
				}

			1/lfo[which_lfo].frequency => float div_click;
			div_click * 0.48828125::ms => now;

		} else if (lfo[which_lfo].type==2) {	/// Sawtooth function

			if (lfo[which_lfo].value < 1023){
					lfo[which_lfo].value + 1 => lfo[which_lfo].value;
				} else {
					0 => lfo[which_lfo].value;
				}

			1/lfo[which_lfo].frequency => float div_click;
			div_click * 0.9765625::ms => now;

		} else if (lfo[which_lfo].type==3) {	/// Reverse Sawtooth function

				if (lfo[which_lfo].value > 0){
						lfo[which_lfo].value - 1 => lfo[which_lfo].value;
					} else {
						1023 => lfo[which_lfo].value;
					}

				1/lfo[which_lfo].frequency => float div_click;
				div_click * 0.9765625::ms => now;

			} else {				/// Square function

			if (direction > 2000){
				1 => direction;
			}

			if (direction < 1000){
				1023 => lfo[which_lfo].value;

			} else {
				0 => lfo[which_lfo].value;
			}

			direction + 1 => direction;

			1/lfo[which_lfo].frequency => float div_click;
			div_click * 0.5::ms => now;

		}
	}
}

fun void clock_pulse(){
		0 => pulse;
		50::ms => now;
		1023 => pulse;
}

fun void lfo_sampler(int maxlfo){

	0.001953125 => float step_multiplier; // 0.001953125 * 512 = 1

	while (true){

		for ((maxx-1) => int i; i>0; i--){
			for (0=> int o; o<maxlfo; o++){
				lfo[o].value_table[i-1] => lfo[o].value_table[i];
			}
		}

		for (0=> int o; o<maxlfo; o++){
			lfo[o].value => lfo[o].value_table[0];
		}

		for (0=> int x; x<maxx; x++){

			for (0=> int y; y<maxy; y++){

				for (0=> int l; l<layers; l++){

					if (grid[l].matrix[x][y]){

						if (lfo[grid[l].lfo].value_table[x]>512){		// If LFO is positive
							lfo[grid[l].lfo].value_table[x] - 512 => int lfo_value;
							lfo_value * (step_multiplier*grid[l].lfo_steps[x]) => float multiplier;
							multiplier $ int => int final_val;
							final_val => grid[l].lfo_value[x];
						} else {					// If LFO is negative
							lfo[grid[l].lfo].value_table[x]  - 511 => int lfo_value;
							lfo_value * -1 => lfo_value;
							lfo_value * (step_multiplier*grid[l].lfo_steps[x]) => float multiplier;
							multiplier $ int => int final_val;
							final_val => grid[l].lfo_value[x];
						}
					}
				}
			}
		}
		//(glfo_sample_latency/glfo1_f)::ms => now;
		glfo_sample_latency::ms => now;
	}

}

/// Colate data for Octomod at latency intervals and send OSC data to Send routine
fun void octoModulate(){

	while (true){
			//octSend(glfo8,glfo7,glfo6,glfo5,glfo4,glfo3,glfo2,glfo1);
			// FIX: check for less than 8 LFOs!!

			if (enable_clockpulse==1 || enable_layerpulse == 1)
				octSend(pulse,lfo[6].value,lfo[5].value,lfo[4].value,lfo[3].value,lfo[2].value,lfo[1].value,lfo[0].value);
			else
				octSend(lfo[7].value,lfo[6].value,lfo[5].value,lfo[4].value,lfo[3].value,lfo[2].value,lfo[1].value,lfo[0].value);

			goct_lat::ms => now; // Octomod update frequency
	}

}

/// Send data to Octomod
fun void octSend(int oa, int ob, int oc, int od, int oe, int of, int og, int oh){

	oemit.startMsg(omprefix, "iiiiiiii");

	oa => oemit.addInt;
    ob => oemit.addInt;
    oc => oemit.addInt;
	od => oemit.addInt;
    oe => oemit.addInt;
    of => oemit.addInt;
	og => oemit.addInt;
	oh => oemit.addInt;

}

class modLFO{

	0 => int value;
	0 => int type;
	0.5 => float frequency;
	int value_table[maxx];

}


public class noteGrid{

    int matrix[maxx][maxy];

	1           => int direction;
    maxx        => int steps;
	100 		=> int channel_volume;
    4           => int time_sig;
	3			=> int time_sig_table_pos;
    time_sig    => int time_sync;       /// This is the previous time_sig value, used by MidiNote
    1           => int channel;
    0           => int scale;
    0           => int transpose;
    12          => int transpose_step;
	8			=> int transpose_table_pos;
	0			=> int mute;
	cc1			=> int cc1_value;
	cc2			=> int cc2_value;
	0			=> int swing;
	0			=> int swing_state;
	0			=> int swing_sync;		/// This is the previous swing value
	0			=> int lfo;				/// Which LFO to modulate the layer

	dur tick_time;
	int lfo_value[maxx];

	int skip_steps[maxx];				// Trigger for whether a step is played
	for (0=> int i; i < maxx; i++)
		0 => skip_steps[i];

	int velocity_steps[maxx];
	for (0=> int i; i < maxx; i++)
		maxy - 4 => velocity_steps[i];

	int lfo_steps[maxx];				/// LFO modulation amount
	for (0=> int i; i < maxx; i++)
		 1 => lfo_steps[i];

	int prb_steps[maxx];				/// Probability defaults
	for (0=> int i; i < maxx; i++)
		 8 => prb_steps[i];

	int cc1_steps[maxx];				/// MIDI Control 1 defaults
	for (0=> int i; i < maxx; i++)
		 1 => cc1_steps[i];

	int cc2_steps[maxx];				/// MIDI Control 2 defaults
	for (0=> int i; i < maxx; i++)
		 1 => cc2_steps[i];

}

class mChannel{

	maxx - 5 => int volume;

}

class mScales{
    16  => int maxtables;
    256 => int maxscale;
    int table[maxtables][maxscale];

    // BY DEFAULT, THESE SCALES ONLY WORK ON THE 64 AND 128.
    // BUT IT SHOULD BE EASY TO CUSTOMISE THESE FOR THE 256.

    // SCALE DEFINITION: Default for all tables: An ordinary scale
    for (0=> int j; j < maxtables; j++)
        for (0 => int i; i < maxscale; i++)
            i => table[j][i];

    ///SCALE DEFINITION: Slightly Tighter
    68 => table[1][64];
    67 => table[1][63];
    65 => table[1][62];
    63 => table[1][61];
    61 => table[1][60];
    60 => table[1][59];
    58 => table[1][58];
    56 => table[1][57];

    ///SCALE DEFINITION: Slightly Wider
    84 => table[2][64];
    80 => table[2][63];
    76 => table[2][62];
    72 => table[2][61];
    68 => table[2][60];
    64 => table[2][59];
    60 => table[2][58];
    56 => table[2][57];

    ///SCALE DEFINITION: Slightly Wider w/Octave Shift
    84 => table[3][64];
    68 => table[3][63];
    76 => table[3][62];
    60 => table[3][61];
    66 => table[3][60];
    52 => table[3][59];
    62 => table[3][58];
    44 => table[3][57];

    ///SCALE DEFINITION: Ableton Drum/Operator mapping
    43 => table[7][64];
    42 => table[7][63];
    41 => table[7][62];
    40 => table[7][61];
    39 => table[7][60];
    38 => table[7][59];
    37 => table[7][58];
    36 => table[7][57];

    ///SCALE DEFINITION: Ableton Drum/Operator mapping
    51 => table[8][64];
    50 => table[8][63];
    49 => table[8][62];
    48 => table[8][61];
    47 => table[8][60];
    46 => table[8][59];
    45 => table[8][58];
    44 => table[8][57];

    ///SCALE DEFINITION: GM Drums for channel 10
    64 => table[9][64];
    63 => table[9][63];
    62 => table[9][62];
    48 => table[9][61];
    60 => table[9][60];
    37 => table[9][59];
    36 => table[9][58];
    35 => table[9][57];

}
