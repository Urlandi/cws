#####
# Simple web cli for cisco ios
#####

# Const
set maxparams 2
set minport 0
set maxport 65535
set programname {Simple web cli}
set connwait 900000

# Var
set retcode 0
set listenaddr {}
set listenport 0

# Procedures

# HTTP response
proc response_http { sockaddr { mode 0 } } {
	set httpver {HTTP/1.0 }
	set httpcode [list {200 OK} {501 Not Implemented}]
	set httpopt [list \
						{Content-Type: text/html} \
						{Connection: close} \
						{} \
				]

	puts -nonewline $sockaddr $httpver
	puts $sockaddr [lindex $httpcode $mode]
	foreach r $httpopt { puts $sockaddr $r }
}

# Print html page
proc response_html { sockaddr { body 0 }  { cmdline {} } { msgout {} } { checked {} } } {
	global programname
	
	set	htmltitle "<html><head><title>$programname</title></head><body>"
	set htmlbody [list [list \
					{<form action="/" method="get">} \
					"<input type=\"text\" name=\"cmd\" maxlength=\"160\" size=\"40\" value=\"$cmdline\">" \
					"<input type=\"submit\" value=\"Run\"><input type=\"checkbox\" name=\"tclsh\" $checked>tclsh</form>" \
					{<form action="/close" method="get"><input type="submit" value="Stop"></form>}] \
						[list \
					{<p><h1>Stopped</h1></p>}] \
						[list \
					{<p><h1>Not Implemented</h1></p><a href="/">back</a>}]]
	set htmlclose {</body></html>}
	
	puts $sockaddr $htmltitle	
	if [string length $msgout] then { 
		puts $sockaddr "<textarea readonly cols=\"40\" rows=\"12\" wrap=\"off\">$msgout</textarea>"
	}
	foreach r [lindex $htmlbody $body] { puts $sockaddr $r }	
	puts $sockaddr $htmlclose
}

# Decode url
# From http://wiki.tcl.tk/14144 by Harald Oehlmann, some fix and update
proc expandPercent {data} {
    set pos 0
	set data [string map [list + { } "\\" "\\\\"] $data]

	while { -1 != [set pos [string first "%" $data $pos]]} {
        set hexNumber "0x[string range $data [expr $pos + 1] [expr $pos+ 2]]"
        if { 4 == [string length $hexNumber] && [string is integer $hexNumber] } then {              
            set data [string range $data 0 [expr $pos - 1]][format %c $hexNumber][string range $data [expr $pos + 3] end]  
        }
		incr pos
    }
    return $data
}

# Listen for new connections
proc get_http { sockaddr ipaddr portaddr } {	
	global stopsrv
	global connwait
	
	set mode {0}
	set body {0}	
	set msgout {}
	set cmdline {}
	set checked {}
	
	gets $sockaddr r
	flush $sockaddr
	set rs [string tolower [string trim $r]]
	
	after cancel set stopsrv 2
	after $connwait set stopsrv 2
	
	switch -regexp -- $rs {
		{^get\s*/close} { set body 1; set stopsrv 0	}
		{^get\s*/\s+} {	puts "GET from $ipaddr:$portaddr"; after cancel set stopsrv 1 }
		{^get\s*/\?cmd=} {
			if { [regexp -nocase {/\?cmd=([^[:space:]^\&]*)(&tclsh)?} $r opt cmdline checked]
				&& [string length $cmdline] } then {
				set cmdline [expandPercent $cmdline]
				if { ! [string length $checked] } then {					
					catch "exec $cmdline" msgout
				} else {
					catch $cmdline msgout
					set checked {checked}
				}
			}
		}
		default { set mode 1; set body 2 }
	}
	response_http $sockaddr $mode
	response_html $sockaddr $body $cmdline $msgout $checked
	close $sockaddr
}

# Help like cisco
proc show_help { c s } {
	global minport
	global maxport
			
	set msg [list \
				"A.B.C.D or *\tListen ip address" \
				"<$minport-$maxport>\tListen tcp port, 0 for first free"]					
	set msgc [llength $msg]
	
	if { $c < $msgc } then { puts [lindex $msg $c] }
	if { ! $s } then { puts {<cr>} }
}

# Error on input
proc show_err { c } {	
	global maxparams
		
	set msgerrhd {% Invalid input detected in}
	set msgerrtl {param}
	set msgerr [list {address} {port} {extra}]
	
	if { $c > $maxparams } then { set c $maxparams }
	puts "$msgerrhd [lindex $msgerr $c] $msgerrtl"
}

# Check parameters
proc check_params { c p } {
	global minport
	global maxport
	global maxparams
	
	set reip {^(2(2[0-3]|[0-1]\d)|1\d{2}|[1-9]\d{0,1})(\.(2(5[0-5]|[0-4]\d)|1\d{2}|[1-9]\d|\d)){3}$}
	
	if { ($c < $maxparams) &&
		 (! $c && ([regexp $reip $p] || [string equal -nocase -length 1 $p {*}])) ||
		 ($c && ($p>=$minport && $p<=$maxport)) 
	} then { return {1} 
	} else { return {0} }
}

# Main

# Count of complete read parameters
set i 0

# Read parameters: <listen ipaddress> <listen port>
if { $argc > 0 } then {
	set c [expr $argc - 1]
	
	foreach p $argv {
		if { ($c == $i) && [regexp {(.*)\?\s*$} $p t s] } then { 
			set l [string length $s]
			if { $i >= $maxparams } then { set l 0}
			show_help $i $l
			break
		}
		if [check_params $i $p] then { 
			if { $i } then {
				set listenport $p
			} else {
				if { ! [string equal -nocase -length 1 $p {*}] } then {
					set listenaddr $p
				}
			}
			incr i
		} else {
			show_err $i
			break
		}
	}
}

# Listen socket or exit
if { $argc == $i } then {
	if [string length $listenaddr] then {
		set wsh [socket -server get_http -myaddr $listenaddr $listenport]
	} else {
		set wsh [socket -server get_http $listenport]
	}
	set sockparam [fconfigure $wsh -sockname]
	puts "Listen on http://[lindex $sockparam 0]:[lindex $sockparam 2]"
	after $connwait set stopsrv 1
	vwait stopsrv
	close $wsh
	set retcode $stopsrv
} else {
	set retcode [expr $i + 100]
}
return $retcode