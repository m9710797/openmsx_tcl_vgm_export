namespace eval vgm {
variable active false

variable psg_register
variable opll_register
variable y8950_register
variable opl4_register_wave
variable opl4_register_1
variable opl4_register_2

variable start_time 0
variable tick_time 0
variable ticks
variable music_data
variable file_name
variable original_filename
variable directory [file normalize $::env(OPENMSX_USER_DATA)/../vgm_recordings]

variable psg_logged       false
variable fm_logged        false
variable y8950_logged     false
variable moonsound_logged false
variable scc_logged       false

variable abort            false

variable scc_plus_used

variable watchpoints [list]

variable active_fm_register -1

variable loop_watch_point
variable loop_amount 0
variable position 0

variable auto_next false

variable file_number 1

variable mbwave_title_hack       false
variable mbwave_loop_hack	 false
variable mbwave_basic_title_hack false

variable supported_chips [list MSX-Music PSG Moonsound MSX-Audio SCC]

proc little_endian_32 {value} {
	binary format i $value
}

proc zeros {value} {
	string repeat "\0" $value
}

set_tabcompletion_proc vgm_rec [namespace code tab_vgmrec]

proc tab_vgmrec {args} {
	variable supported_chips
	if { [lsearch -exact $args "enable_hack"] >= 0 } {
		concat MBWave_title MBWave_loop MBWave_basic_title
	} else {
		if { [lsearch -exact $args "start"] >= 0 } {
			concat $supported_chips
		} else {
			concat start stop abort next auto_next prefix enable_hack disable_hacks
		}
	}
}

proc set_next_filename {} {
	variable original_filename
	variable directory
	variable file_name [utils::get_next_numbered_filename $directory $original_filename ".vgm"]
}

proc vgm_rec_set_filename {filename} {
	variable original_filename

	if {[string last ".vgm" $filename] == -1} {
		set original_filename $filename
	} else {
		set original_filename [string trim $filename ".vgm"]
	}
	set_next_filename
}

vgm_rec_set_filename "music"

set_help_text vgm_rec \
"Starts recording VGM data. Most of the time this needs to be started before sound
chip initialisation, otherwise it won't work.
Supported soundchips: AY8910 (PSG), YM2413 (FMPAC, MSX-Music),
Y8950 (Music Module, MSX-Audio), YMF278B (OPL4, Moonsound) and Konami SCC(+).
Files will be stored in the openMSX home directory in a subdirectory vgm_recordings
There a many parameters, use tab completion: vgm_rec [tab_vgmrec]
Defaults: Record to music0001.vgm or music0002.vgm if that exists etc.
You must end a recording with vgm_rec stop, otherwise the VGM file will be empty.
There are many more parameters and features available, additional information at:
https://github.com/niekvlessert/openmsx_tcl_vgm_export/blob/master/README.md
"

proc vgm_rec {args} {
	variable abort            false
	variable active
	variable auto_next

	variable mbwave_title_hack
	variable mbwave_loop_hack
	variable mbwave_basic_title_hack

	variable psg_logged
	variable fm_logged
	variable y8950_logged
	variable moonsound_logged
	variable scc_logged

	set prefix_index [lsearch -exact $args "prefix"]
	if {$prefix_index >= 0 && $prefix_index < ([llength $args] - 1)} {
		set prefix [lindex $args [expr {$prefix_index + 1}]]
		set args [lreplace $args $prefix_index [expr {$prefix_index + 1}]]
		vgm_rec_set_filename $prefix
		return
	}

	set hack_index [lsearch -exact $args "enable_hack"]
	if {$hack_index >= 0} {
		if {$hack_index < ([llength $args] - 1)} {
			set hack [lindex $args [expr {$prefix_index + 1}]]
			set args [lreplace $args $hack_index [expr {$prefix_index + 1}]]
			foreach a $args {
				if     {[string compare -nocase $a "MBWave_title"      ] == 0} {set mbwave_title_hack       true} \
				elseif {[string compare -nocase $a "MBWave_loop"       ] == 0} {set mbwave_loop_hack        true} \
				elseif {[string compare -nocase $a "MBWave_basic_title"] == 0} {set mbwave_basic_title_hack true} \
				else {error "Hack not recognized, use tab completion"}
			}
			if { ($mbwave_title_hack || $mbwave_loop_hack) && ($mbwave_basic_title_hack) } {
				vgm::vgm_disable_hacks
				error "Don't combine those hacks... all hacks disabled to avoid problems"
			}
			puts "Enabled hack(s): $args."
			return
		} else {error "Please specify hack to activate, use tab completion"}
	}

	set index [lsearch -exact $args "disable_hacks"]
	if {$index >= 0} {
		vgm::vgm_disable_hacks
		puts "Disabled all hacks."
		return
	}

	set index [lsearch -exact $args "auto_next"]
	if {$index >= 0} {
		set args [lreplace $args $index [expr {$index}]]
		set auto_next true
		puts "Enabled auto next feature"
		return
	}

	set index [lsearch -exact $args "abort"]
	if {$index >= 0} {
		set args [lreplace $args $index [expr {$index}]]
		set abort true
		vgm::vgm_rec_end
		return
	}

	set index [lsearch -exact $args "stop"]
	if {$index >= 0} {
		set args [lreplace $args $index [expr {$index}]]
		vgm::vgm_rec_end
		return
	}

	set index [lsearch -exact $args "next"]
	if {$index >= 0} {
		set args [lreplace $args $index [expr {$index}]]
		vgm::vgm_rec_next
		return
	}

	if {[llength $args] == 0} {
		variable supported_chips
		error "Please specify one or more music chips you want to record VGM data from:\nvgm_rec $supported_chips"
	}

	set index [lsearch -exact $args "start"]
	if {$index >= 0} {
		if {!$active} {
			if {$index < ([llength $args] - 1)} {
				puts "args found... $args"
				set args [lreplace $args $index [expr {$index}]]

				set psg_logged 		false
				set fm_logged 		false
				set y8950_logged 	false
				set moonsound_logged 	false
				set scc_logged		false

				foreach a $args {
					if     {[string compare -nocase $a "PSG"      ] == 0} {set psg_logged       true} \
					elseif {[string compare -nocase $a "MSX-Music"] == 0} {set fm_logged        true} \
					elseif {[string compare -nocase $a "MSX-Audio"] == 0} {set y8950_logged     true} \
					elseif {[string compare -nocase $a "Moonsound"] == 0} {set moonsound_logged true} \
					elseif {[string compare -nocase $a "SCC"      ] == 0} {set scc_logged       true} \
					else {error "Please choose a valid chip to record, use tab completion"}
				}
			} else {
				if {!$psg_logged && !$fm_logged && !$y8950_logged && !$moonsound_logged && !$scc_logged} { error "Please choose at least one chip to record for, use tab completion" }
			}
			vgm::vgm_rec_start
			return
		} else {
			error "Already recording, please stop it before running start again"
		}
	}

	error "Invalid input detected, use tab completion"
}

proc vgm_disable_hacks {} {
        variable mbwave_title_hack
        variable mbwave_loop_hack
        variable mbwave_basic_title_hack

	set mbwave_title_hack       false
	set mbwave_loop_hack        false
	set mbwave_basic_title_hack false
}


proc vgm_rec_start {} {
	variable active
	if {$active} {
		error "Already recording."
	}
	set active true

	variable auto_next
	if { $auto_next } {
		vgm::vgm_check_audio_data_written
	}

	variable mbwave_loop_hack
	if { $mbwave_loop_hack } { vgm::vgm_log_loop_point }

	set_next_filename
	variable directory
	file mkdir $directory

	variable psg_register       -1
	variable fm_register        -1
	variable y8950_register     -1
	variable opl4_register_wave -1
	variable opl4_register_1    -1
	variable opl4_register_2    -1

	variable ticks 0
	variable music_data ""

	variable scc_plus_used false

	variable watchpoints
	variable psg_logged
	if {$psg_logged} {
		lappend watchpoints [debug set_watchpoint write_io 0xA0 {} {vgm::write_psg_address}]
		lappend watchpoints [debug set_watchpoint write_io 0xA1 {} {vgm::write_psg_data}]
	}

	variable fm_logged
	if {$fm_logged} {
		lappend watchpoints [debug set_watchpoint write_io 0x7C {} {vgm::write_opll_address}]
		lappend watchpoints [debug set_watchpoint write_io 0x7D {} {vgm::write_opll_data}]
	}

	variable y8950_logged
	if {$y8950_logged} {
		lappend watchpoints [debug set_watchpoint write_io 0xC0 {} {vgm::write_y8950_address}]
		lappend watchpoints [debug set_watchpoint write_io 0xC1 {} {vgm::write_y8950_data}]
	}

	# A thing: for wave to work some bits have to be set through FM2. So
	# that must be logged. This logs all, but just so you know...
	# Another thing: FM data can be used by FM bank 1 and FM bank 2. FM
	# data has a mirror however
	# So programs can use both ports in different ways; all to FM data,
	# FM1->FM-data,FM2->FM-data-mirror, etc. 4 options.
	# http://www.msxarchive.nl/pub/msx/docs/programming/opl4tech.txt
	variable moonsound_logged
	if {$moonsound_logged} {
		lappend watchpoints [debug set_watchpoint write_io 0x7E {} {vgm::write_opl4_address_wave}]
		lappend watchpoints [debug set_watchpoint write_io 0x7F {} {vgm::write_opl4_data_wave}]
		lappend watchpoints [debug set_watchpoint write_io 0xC4 {} {vgm::write_opl4_address_1}]
		lappend watchpoints [debug set_watchpoint write_io 0xC5 {} {vgm::write_opl4_data}]
		lappend watchpoints [debug set_watchpoint write_io 0xC6 {} {vgm::write_opl4_address_2}]
		lappend watchpoints [debug set_watchpoint write_io 0xC7 {} {vgm::write_opl4_data}]
	}

	variable scc_logged
	if {$scc_logged} {
		foreach {ps ss plus} [find_all_scc] {
			if {$plus} {
				lappend watchpoints [debug set_watchpoint write_mem {0xB800 0xB8AF} "\[watch_in_slot $ps $ss\]" {vgm::scc_plus_data}]
			} else {
				lappend watchpoints [debug set_watchpoint write_mem {0x9800 0x988F} "\[watch_in_slot $ps $ss\]" {vgm::scc_data}]
			}
		}
	}

	variable file_name
	set recording_text "VGM recording initiated, start playback now, data will be recorded to $file_name for the following sound chips:"
	if {$psg_logged      } {append recording_text " PSG"       }
	if {$fm_logged       } {append recording_text " MSX-Music" }
	if {$y8950_logged    } {append recording_text " MSX-Audio" }
	if {$moonsound_logged} {append recording_text " Moondsound"}
	if {$scc_logged      } {append recording_text " SCC"       }
	puts $recording_text
	message $recording_text
}

proc find_all_scc {} {
	set result [list]
	for {set ps 0} {$ps < 4} {incr ps} {
		for {set ss 0} {$ss < 4} {incr ss} {
			set device_list [machine_info slot $ps $ss 2]
			if {[llength $device_list] != 0} {
				set device [lindex $device_list 0]
				set device_info_list [machine_info device $device]
				lassign $device_info_list device_info device_sub_info
				if {[string match -nocase *scc* $device_info]} {
					lappend result $ps $ss 1
				}
				if {[string match -nocase *scc* $device_sub_info] ||
				    [string match -nocase manbow2 $device_sub_info] ||
				    [string match -nocase KonamiUltimateCollection $device_sub_info]} {
					lappend result $ps $ss 0
				}
			}
			if {![machine_info issubslotted $ps]} break
		}
	}
	return $result
}

proc write_psg_address {} {
	variable psg_register $::wp_last_value
}

proc write_psg_data {} {
	variable psg_register
	if {$psg_register >= 0 && $psg_register < 14} {
		update_time
		variable music_data
		append music_data [binary format ccc 0xA0 $psg_register $::wp_last_value]
	}
}

proc write_opll_address {} {
	variable opll_register $::wp_last_value
}

proc write_opll_data {} {
	variable opll_register
	if {$opll_register >= 0} {
		update_time
		variable music_data
		append music_data [binary format ccc 0x51 $opll_register $::wp_last_value]
	}
}

proc write_y8950_address {} {
	variable y8950_register $::wp_last_value
}

proc write_y8950_data {} {
	variable y8950_register
	if {$y8950_register >= 0} {
		update_time
		variable music_data
		append music_data [binary format ccc 0x5C $y8950_register $::wp_last_value]
	}
}

proc write_opl4_address_wave {} {
	variable opl4_register_wave $::wp_last_value
}

proc write_opl4_data_wave {} {
	variable opl4_register_wave
	if {$opl4_register_wave >= 0} {
		update_time
		# VGM spec: Port 0 = FM1, port 1 = FM2, port 2 = Wave. It's
		# based on the datasheet A1 & A2 use.
		variable music_data
		append music_data [binary format cccc 0xD0 0x2 $opl4_register_wave $::wp_last_value]
	}
}

proc write_opl4_address_1 {} {
	variable opl4_register_1 $::wp_last_value
	variable active_fm_register 1
}

proc write_opl4_data {} {
	variable opl4_register_1
	variable opl4_register_2
	variable active_fm_register
	variable music_data

	if {($opl4_register_1 >= 0 && $active_fm_register == 1)} {
		update_time
		append music_data [binary format cccc 0xD0 0x0 $opl4_register_1 $::wp_last_value]
	}
	if {($opl4_register_2 >= 0 && $active_fm_register == 2)} {
		update_time
		append music_data [binary format cccc 0xD0 0x1 $opl4_register_2 $::wp_last_value]
	}
}

proc write_opl4_address_2 {} {
	variable opl4_register_2 $::wp_last_value
	variable active_fm_register 2
}

proc scc_data {} {
	# Thanks ValleyBell, BiFi

	# if 9800h is written, waveform channel 1   is set in 9800h - 981fh, 32 bytes
	# if 9820h is written, waveform channel 2   is set in 9820h - 983fh, 32 bytes
	# if 9840h is written, waveform channel 3   is set in 9840h - 985fh, 32 bytes
	# if 9860h is written, waveform channel 4,5 is set in 9860h - 987fh, 32 bytes
	# if 9880h is written, frequency channel 1 is set in 9880h - 9881h, 12 bits
	# if 9882h is written, frequency channel 2 is set in 9882h - 9883h, 12 bits
	# if 9884h is written, frequency channel 3 is set in 9884h - 9885h, 12 bits
	# if 9886h is written, frequency channel 4 is set in 9886h - 9887h, 12 bits
	# if 9888h is written, frequency channel 5 is set in 9888h - 9889h, 12 bits
	# if 988ah is written, volume channel 1 is set, 4 bits
	# if 988bh is written, volume channel 2 is set, 4 bits
	# if 988ch is written, volume channel 3 is set, 4 bits
	# if 988dh is written, volume channel 4 is set, 4 bits
	# if 988eh is written, volume channel 5 is set, 4 bits
	# if 988fh is written, channels 1-5 on/off, 1 bit

	#VGM port format:
	#0x00 - waveform
	#0x01 - frequency
	#0x02 - volume
	#0x03 - key on/off
	#0x04 - waveform (0x00 used to do SCC access, 0x04 SCC+)
	#0x05 - test register

	update_time

	variable music_data
	if {0x9800 <= $::wp_last_address && $::wp_last_address < 0x9880} {
		append music_data [binary format cccc 0xD2 0x0 [expr {$::wp_last_address - 0x9800}] $::wp_last_value]
	}
	if {0x9880 <= $::wp_last_address && $::wp_last_address < 0x988A} {
		append music_data [binary format cccc 0xD2 0x1 [expr {$::wp_last_address - 0x9880}] $::wp_last_value]
	}
	if {0x988A <= $::wp_last_address && $::wp_last_address < 0x988F} {
		append music_data [binary format cccc 0xD2 0x2 [expr {$::wp_last_address - 0x988A}] $::wp_last_value]
	}
	if {$::wp_last_address == 0x988F} {
		append music_data [binary format cccc 0xD2 0x3 0x0 $::wp_last_value]
	}
}

proc scc_plus_data {} {
	# if b800h is written, waveform channel 1 is set in b800h - b81fh, 32 bytes
	# if b820h is written, waveform channel 2 is set in b820h - b83fh, 32 bytes
	# if b840h is written, waveform channel 3 is set in b840h - b85fh, 32 bytes
	# if b860h is written, waveform channel 4 is set in b860h - b87fh, 32 bytes
	# if b880h is written, waveform channel 5 is set in b880h - b89fh, 32 bytes
	# if b8a0h is written, frequency channel 1 is set in b8a0h - b8a1h, 12 bits
	# if b8a2h is written, frequency channel 2 is set in b8a2h - b8a3h, 12 bits
	# if b8a4h is written, frequency channel 3 is set in b8a4h - b8a5h, 12 bits
	# if b8a6h is written, frequency channel 4 is set in b8a6h - b8a7h, 12 bits
	# if b8a8h is written, frequency channel 5 is set in b8a8h - b8a9h, 12 bits
	# if b8aah is written, volume channel 1 is set, 4 bits
	# if b8abh is written, volume channel 2 is set, 4 bits
	# if b8ach is written, volume channel 3 is set, 4 bits
	# if b8adh is written, volume channel 4 is set, 4 bits
	# if b8aeh is written, volume channel 5 is set, 4 bits
	# if b8afh is written, channels 1-5 on/off, 1 bit

	#VGM port format:
	#0x00 - waveform
	#0x01 - frequency
	#0x02 - volume
	#0x03 - key on/off
	#0x04 - waveform (0x00 used to do SCC access, 0x04 SCC+)
	#0x05 - test register

	update_time

	variable music_data
	if {0xB800 <= $::wp_last_address && $::wp_last_address < 0xB8A0} {
		append music_data [binary format cccc 0xD2 0x4 [expr {$::wp_last_address - 0xB800}] $::wp_last_value]
	}
	if {0xB8A0 <= $::wp_last_address && $::wp_last_address < 0xb8aa} {
		append music_data [binary format cccc 0xD2 0x1 [expr {$::wp_last_address - 0xB8A0}] $::wp_last_value]
	}
	if {0xB8AA <= $::wp_last_address && $::wp_last_address < 0xB8AF} {
		append music_data [binary format cccc 0xD2 0x2 [expr {$::wp_last_address - 0xB8AA}] $::wp_last_value]
	}
	if {$::wp_last_address == 0xB8AF} {
		append music_data [binary format cccc 0xD2 0x3 0x0 $::wp_last_value]
	}

	variable scc_plus_used true
}

proc update_time {} {
	variable start_time
	if {$start_time == 0} {
		set start_time [machine_info time]
		set msg "VGM recording started, data was written to one of the sound chips recording for."
		puts $msg
		message $msg
	}

	variable tick_time
	set tick_time [machine_info time]
	set new_ticks [expr {int(($tick_time - $start_time) * 44100)}]

	variable ticks
	variable music_data
	while {$new_ticks > $ticks} {
		set difference [expr {$new_ticks - $ticks}]
		set step [expr {$difference > 65535 ? 65535 : $difference}]
		incr ticks $step
		append music_data [binary format cs 0x61 $step]
	}
}

proc vgm_rec_end {} {
	variable active
	variable abort

	if {!$active && $abort} {
		set stop_message "VGM recording aborted, no data written..."
		puts $stop_message
		message $stop_message
		return
	}

	if {!$active} {
		error "Not recording."
	}

	# remove all watchpoints that were created
	variable watchpoints
	foreach watch $watchpoints {
		if {[catch {
			debug remove_watchpoint $watch
		} errorText]} {
			puts "Failed to remove watchpoint $watch... using savestates maybe? Continue anyway."
		}
	}
	variable watchpoints [list]

	if {!$abort} {

		update_time

		variable tick_time
		set tick_time 0

		variable music_data
		variable temp_music_data ""

		variable moonsound_logged
		if {$moonsound_logged} {
			set moonsound_ram [concat [machine_info output_port 0x7E] {wave RAM}]
			if {[lsearch -exact [debug list] $moonsound_ram] >= 0} {
				set moonsound_ram_size [debug size $moonsound_ram]
				if {$moonsound_ram_size > 0} {
					append temp_music_data [binary format ccc 0x67 0x66 0x87]
					append temp_music_data [little_endian_32 [expr $moonsound_ram_size + 8]]
					append temp_music_data [little_endian_32 $moonsound_ram_size]
					append temp_music_data [zeros 4]
					append temp_music_data [debug read_block $moonsound_ram 0 $moonsound_ram_size]

					# enable OPL4 mode so it's enabled even if recorded vgm data won't do that
					append temp_music_data [binary format cccc 0xD0 0x01 0x05 0x03]
				}
			}
		}

		variable y8950_logged
		if { $y8950_logged } {
			set y8950_ram [concat [machine_info output_port 0xC0] RAM]
			if {[lsearch -exact [debug list] $y8950_ram] >= 0} {
				set y8950_ram_size [debug size $y8950_ram]
				if {$y8950_ram_size > 0} {
					append temp_music_data [binary format ccc 0x67 0x66 0x88]
					append temp_music_data [little_endian_32 [expr $y8950_ram_size + 8]]
					append temp_music_data [little_endian_32 $y8950_ram_size]
					append temp_music_data [zeros 4]
					append temp_music_data [debug read_block $y8950_ram 0 $y8950_ram_size]
				}
			}
		}

		append temp_music_data $music_data
		append temp_music_data [binary format c 0x66]

		set header "Vgm "
		# file size
		append header [little_endian_32 [expr {[string length $temp_music_data] + 0x100 - 4}]]
		# VGM version 1.7
		append header [little_endian_32 0x170]
		append header [zeros 4]

		# YM2413 clock
		variable fm_logged
		if {$fm_logged} {
			append header [little_endian_32 3579545]
		} else {
			append header [zeros 4]
		}

		append header [zeros 4]
		# Number of ticks
		variable ticks
		append header [little_endian_32 $ticks]
		set ticks 0
		append header [zeros 24]
		# Data starts at offset 0x100
		append header [little_endian_32 [expr {0x100 - 0x34}]]
		append header [zeros 32]

		# Y8950 clock
		if {$y8950_logged} {
			append header [little_endian_32 3579545]
		} else {
			append header [zeros 4]
		}

		append header [zeros 4]

		# YMF278B clock
		if {$moonsound_logged} {
			append header [little_endian_32 33868800]
		} else {
			append header [zeros 4]
		}

		append header [zeros 16]

		# AY8910 clock
		variable psg_logged
		if {$psg_logged} {
			append header [little_endian_32 1789773]
		} else {
			append header [zeros 4]
		}

		append header [zeros 36]

		# SCC clock
		variable scc_logged
		if {$scc_logged} {
			set scc_clock 1789773
			variable scc_plus_used
			if {$scc_plus_used} {
				# enable bit 31 for SCC+ support, that's how it's done
				# in VGM I've been told. Thanks Grauw.
				set scc_clock [expr {$scc_clock | 1 << 31}]
			}
			append header [little_endian_32 $scc_clock]
		} else {
			append header [zeros 4]
		}

		append header [zeros 96]

		variable file_name
		variable directory

		# Title hacks

		# Mbwave Title
		variable mbwave_title_hack
		if {$mbwave_title_hack} {set title_address 0xffc6}

		# Mbwave basic driver
		variable mbwave_basic_title_hack
		if {$mbwave_title_hack} {set title_address 0xc0dc}

		if {$mbwave_title_hack || $mbwave_basic_title_hack} {
			set file_name [string map {/ -} [debug read_block "Main RAM" $title_address 0x32]]
			set file_name [string trim $file_name]
			set file_name [format %s%s%s%s $directory "/" $file_name ".vgm"]
		}

		set file_handle [open $file_name "w"]
		fconfigure $file_handle -encoding binary -translation binary
		puts -nonewline $file_handle $header
		puts -nonewline $file_handle $temp_music_data
		close $file_handle


		set stop_message "VGM recording stopped, wrote data to $file_name."
	} else {
		set stop_message "VGM recording aborted, no data written..."
	}

	puts $stop_message
	message $stop_message

	set active false

	variable start_time
	set start_time 0

	variable loop_amount
	set loop_amount 0
}

proc vgm_rec_next {} {
	variable active
	if {!$active} {
		variable original_filename music
	} else {
		vgm_rec_end
	}

	vgm_rec_start
}

# Generic function to check if audio data is still written when recording is active. If not for a second, assume end recording, and start recording next if this is wanted
proc vgm_check_audio_data_written {} {
	variable tick_time
	variable active
	variable auto_next

	if { $active } {
		set now [machine_info time]
		if { $tick_time == 0 || $now - $tick_time < 1 } {
			after time 1 vgm::vgm_check_audio_data_written
		} else {
			vgm::vgm_rec_end
			if { $auto_next } {
				set auto_next_text "auto_next feature active, starting next recording"
				puts $auto_next_text
				message $auto_next_text
				vgm::vgm_rec_start
			}
		}
	}
}

# Loop point logger for MBWave only
proc vgm_log_loop_point {} {
	variable watchpoints
	lappend watchpoints [debug set_watchpoint write_mem 0x51f7 {} {vgm::vgm_check_loop_point}]
}

proc vgm_check_loop_point {} {
	variable position
	variable loop_amount

        variable start_time
        if {$start_time != 0} {
		set position_new $::wp_last_value
		if { $position_new == 255 } { set position_new 0 }
		if { $position_new < $position } {
			after time 1 vgm::vgm_log_loop_in_music_data
		}
		set position $position_new
	}
}

proc vgm_log_loop_in_music_data {} {
	variable start_time
        if {$start_time != 0} {
		variable loop_amount
		incr loop_amount
		variable music_data
		append music_data [binary format ccc 0xbb 0xbb 0xbb]
		if { $loop_amount == 1 } {
			puts "First loop: Tracklength in seconds (if not using transposing..): [expr [machine_info time]-$start_time]. Marker inserted in VGM file."
		}
		if { $loop_amount == 2 } {
			puts "Second loop. Marker inserted in VGM file."
		}
		if { $loop_amount > 2 } {
			keymatrixdown 7 4
			puts "Third loop occured, stop playback."
			variable position
			set position 0
			set loop_amount 0
			after time 1 { keymatrixup 7 4 }
		}
	}
}

namespace export vgm_rec

}

namespace import vgm::*
