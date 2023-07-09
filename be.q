TMP_LOG:"/tmp/_be_tmp_file.log"	/ Temp file to write stdout to on remote process
LOG_FREQ:1000					/ Frequency to poll for longs (ms)

// Makes q console "become" target process.
// p: conn	{hsym}	:Host:port + optionally :username:password.
be:{[conn]
	if[amI_[];unbe[]]; / Clear, if previously already someone
	id:":"sv 2#1_":"vs string conn; / Sanitize

	out_"Connecting to ",string conn;
	h:@[hopen;conn;::]; / Attempt connection
	if[10h=type h;:out_"Connection failed, err=",h]; / Error
	me_.handle:h; / Otherwise, good to go

	// ID set from remote's perspective, since this may be a portforward, so our notion of the host/port may be
	// different and ultimately not valuable.
	me_.id:me_.handle({string[.z.h],":",string system"p"};`);
	out_"Connected to ",me_.id;

	.z.pi:zpi_; / Override .z.pi
	preq_[];
 }

// Stop pretending to be someone else.
unbe:{[]
	if[not amI_[];:out_"Not anyone"];
	out_"Closing connection to ",me_.id;
	@[hclose;me_.handle;::]; / Close connection
	me_::nobody_; / Erase previous identity
	system"x .z.pi"; / Remove override
 }

// Turn on remote logging.
logOn:{[]
	if[not amI_[];
		out_"Nobody, can't turn on logging";
		:()];

	// Redirect stdout to a temporary file, which we'll poll on a timer.
	//~ Backup timer.
	out_"WARN: Turning on log capture, this fiddles with stdout remotely and the timer locally";
	execOnHandle_[::;(system;"1 ",TMP_LOG)]; / Redirect stdout
	.z.ts:zts_; / Timer to scrap logs
	system"t ",string LOG_FREQ;
 }

// Turn off remote logging.
logOff:{[]
	if[not amI_[];
		out_"Nobody, can't turn off logging";
		:()];

	out_"Turning off log capture";
	logs:execOnHandle_[::;(ztsRemote_;TMP_LOG;0b)]; / One last scrape
	-1 each logs; / Print what we got
	system"x .z.ts"; / Disable timer
	system"t 0";
 }

// Init function.
init_:{[]
	if[`isInit_ in key`.;:()];
	nobody_::(1#.q),(!). flip(
		(`id		;"");
		(`handle	;0Ni));
	me_::nobody_;

	$[()~key`.z.pc;
		.z.pc:zpc_;
		.z.pc:{f x;zpc_ x}];

	isInit_::1b;
 }

// Determines if we are currently being a remote process.
// r:	{bool}	True if remote, false otherwise.
amI_:{[]
	not me_~nobody_
 }

// Simple print message to console.
out_:{[msg]
	-1"local - ",string[.z.Z]," - ",msg;
 }

// Prints remote prefix.
preq_:{[]
	1 me_.id,"-";
 }

// The .z.pi override. Executes commands on the remote host as though it were local.
// p: x	{string}	Command.
// Special syntax:
//	- Commands, unless overridden by a rule below, are run remotely.
//	- Commands starting with "l)" are executed locally.
//	- Commands starting with "r)" are executed remotely. This is an explicit marker to override commands that would
//	  normally default to running locally.
//	- Commands of the form "g)<var>:<cmd>" run '<cmd>' remotely, but assign '<var>' locally. E.g.
//		q)be`:host:1234
//		host:1234-q)g)x:remoteFn[]
//		host:1234-q)unbe[]
//		q)x
//		<output of remoteFn[] run on host:1234>
//	- Commands of the form "s)localFn[...]" execut a local function remotely, with arguments from the remote process.
//	- "be[]", 'unbe[]', and '\\' are run locally unless overridden by "r)".
zpi_:{[x]
	$[
		// Local override.
		x like"l)*";
			show value 2_x;

		// Remote override.
		x like"r)*";
			execOnHandle_[show;2_x];

		// Get override.
		x like"g)*";
			$[(3=count p)&(-11h~type p 1)&(:)~first p:parse 2_x; / Correct format //~ Is count=3 check necessary?
				p[1]set execOnHandle_[::;(eval;last p)];
				out_"Incorrect g) command, should be of the form \"g)variable:command\""];

		// Semi-remote override.
		x like"s)*";
			$[-11h=type f:first p:parse 2_x; / Correct format
				execOnHandle_[show;(eval;value[f],1_p)];
				out_"Incorrect s) command, should be of the form \"s)localFn[...]"];

		// Special commands.
		x~"\\\\\n";
			exit 0;

		1b in first[parse x]~/:`be`unbe`logOn`logOff;
			value x;

		// Else, the default case, run remotely.
			execOnHandle_[show;x]];

	if[amI_[];preq_[]];
 }

// Executes command on remote.
// p: fn	{fn}			What to do with the result.
// p: cmd	{string|list}	Command to execute.
execOnHandle_:{[fn;cmd]
	fn me_.handle cmd / Don't use protected eval because I want to see the error
 }

// The .z.pc override. Detects closure of remote handle.
// p: h	{int}	Handle.
//~ Auto-reconnect?
zpc_:{[h]
	if[h<>me_.handle;:()];
	out_"Connection closed by remote";
	unbe[];
 }

// Timer function to scrape logs on the remote process. This displays the logs here locally and also on the remote
// process to make things as seamless as possible.
zts_:{[]
	logs:execOnHandle_[::;(ztsRemote_;TMP_LOG;1b)];
	-1 each logs;
 }

// Log scraper to run on the remote process (don't call this locally!).
// p: x			{string}	Temp log file where the logs are stashed (see TMP_LOG).
// p: resume	{bool}		Resume log redirect (true) or disable (false).
// r:			{string[]}	Logs.
ztsRemote_:{[x;resume]
	if[()~key f:hsym`$x;:()]; / No logs
	logs:read0 f;
	system"rm ",x;
	system"1 /dev/stdin";
	-1 each logs;
	if[resume;system"1 ",x];
	logs
 }

init_[];

// To-do list:
//	- First prompt after a debug doesn't show prefix.
//	- Ability to run async commands.
//	- Name shows up twice on be within be.
