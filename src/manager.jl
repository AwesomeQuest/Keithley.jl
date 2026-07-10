# global event_list::Vector{String} = []

function getevents()
	global is_selected
	is_selected || nokeithleyselected() || return
	global event_list
	global selected_keithley_type
	noerr = "No error"

	while true
		output = ""
		if keithley_types[selected_keithley_type] == "MODEL 2400"
			@lock gpiblock output = query(KeithleyIO, "STAT:QUE:NEXT?")
		elseif keithley_types[selected_keithley_type] == "MODEL 2470"
			@lock gpiblock output = query(KeithleyIO, "SYST:EVEN:NEXT?")
		else
			@assert false "Unreachable!"
		end
		occursin(noerr, output) && break
		@info output
		push!(event_list, output)
	end
end

function initialize()
	global KeithleyIO
	global is_selected
	is_selected || nokeithleyselected() || return

	
	write(KeithleyIO, "*RST")
	write(KeithleyIO, "SOUR:FUNC VOLT")
	write(KeithleyIO, "SENS:FUNC 'CURR'")
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		write(KeithleyIO, "FORM:ELEM VOLT,CURR")
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		write(KeithleyIO, ":FORM:ASC:PREC 16")
	end
	errormonitor(Threads.@spawn getevents())
end

function monitor(volts_set, maxcurrent)
	global is_selected
	is_selected || nokeithleyselected() || return
	global KeithleyIO
	global rt_is_monitoring
	global rt_cancel_monitor
	global rt_sample_period

	errormonitor(Threads.@spawn getevents())
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		write(KeithleyIO, "SENS:CURR:PROT $(maxcurrent)")
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		write(KeithleyIO, "SOUR:VOLT:ILIMIT $(maxcurrent)")
	else
		@assert false "Unreachable!"
	end
	write(KeithleyIO, "SOUR:VOLT $(volts_set)")
	write(KeithleyIO, "OUTP ON")

	if keithley_types[selected_keithley_type] == "MODEL 2470"
		write(KeithleyIO, "CURR:AZER ON")
		write(KeithleyIO, "VOLT:AZER ON")
		query(KeithleyIO, "MEAS:CURR?")
		query(KeithleyIO, "MEAS:VOLT?")
		write(KeithleyIO, "CURR:AZER OFF")
		write(KeithleyIO, "VOLT:AZER OFF")
	end

	rt_is_monitoring[] = true
	while !rt_cancel_monitor[]
		interuptsleep(rt_sample_period, rt_cancel_monitor, sleep_interupt_interval)
		meascurr, measvolt = "", ""
		global gpiblock
		@lock gpiblock begin
			meascurr = query(KeithleyIO, "MEAS:CURR?")
			measvolt = query(KeithleyIO, "MEAS:VOLT?")
		end
		try
			if keithley_types[selected_keithley_type] == "MODEL 2400"
				_, curr = split(meascurr, ',')
				volt, _ = split(measvolt, ',')
				curr = parse(Float64, curr)
				volt = parse(Float64, volt)
			elseif keithley_types[selected_keithley_type] == "MODEL 2470"
				curr = parse(Float64, meascurr)
				volt = parse(Float64, measvolt)
			else
				curr = volt = 0.0
				@assert false "Unreachable!"
			end
			global plotlock
			@lock plotlock begin
				global rt_times
				global rt_currs
				global rt_volts
				push!(rt_times, now())
				push!(rt_currs, curr)
				push!(rt_volts, volt)
			end
		catch e
			@error e
		end
	end
	rt_is_monitoring[] = false

	write(KeithleyIO, "OUTP OFF")
	errormonitor(Threads.@spawn getevents())
end

function integrated_2400_sweep(min_volts, max_volts, step_voltage, delay, maxcurrent)
	global is_selected
	is_selected || nokeithleyselected() || return
	global KeithleyIO
	global iv_is_sweeping
	global iv_cancel_sweep

	@assert length(min_volts:step_voltage:max_volts) > 2500 "Step size too small. Maximum number of points is 2500, got $(length(min_volts:step_voltage:max_volts))"
	
	data = ""
	@lock gpiblock begin
		write(KeithleyIO, "*RST")
		write(KeithleyIO, "SENS:FUNC:CONC OFF")
		write(KeithleyIO, "SOUR:FUNC VOLT")
		write(KeithleyIO, "SENS:FUNC 'CURR:DC'")
		write(KeithleyIO, "SENS:CURR:PROT $(maxcurrent)")
		write(KeithleyIO, "SOUR:VOLT:STAR $min_volts")
		write(KeithleyIO, "SOUR:VOLT:STOP $max_volts")
		write(KeithleyIO, "SOUR:VOLT:STEP $step_voltage")
		write(KeithleyIO, "SOUR:VOLT:MODE SWE")
		write(KeithleyIO, "SOUR:SWE:RANG AUTO")
		write(KeithleyIO, "SOUR:SWE:SPAC LIN")
		write(KeithleyIO, "TRIG:COUN $(length(min_volts:step_voltage:max_volts))")
		write(KeithleyIO, "SOUR:DEL $delay")
		write(KeithleyIO, "SOUR:SWE:DIR UP")
	
		data = query(KeithleyIO, "READ?")
	end
	data = split(data, ',') .|> x->parse(Float64, x)
	data = reshape(data, 2, :)
	@lock plotlock begin
		global iv_volts, iv_currs
		iv_volts = @view data[1, :]
		iv_currs = @view data[2, :]
	end

	
end

function sweep(min_volts, max_volts, step_voltage, delay, maxcurrent, dual)
	global is_selected
	is_selected || nokeithleyselected() || return
	global KeithleyIO
	global iv_is_sweeping, iv_cancel_sweep
	global selected_keithley_type

	errormonitor(Threads.@spawn getevents())
	global  gpiblock
	@lock gpiblock begin
		if keithley_types[selected_keithley_type] == "MODEL 2400"
			write(KeithleyIO, "SENS:CURR:PROT $(maxcurrent)")
		elseif keithley_types[selected_keithley_type] == "MODEL 2470"
			write(KeithleyIO, "SOUR:VOLT:ILIMIT $(maxcurrent)")
			D = dual ? "ON" : "OFF"
			write(KeithleyIO, "SOUR:SWE:VOLT:LIN:STEP $min_volts, $max_volts, $step_voltage, $delay, 1, AUTO, ON, $D")
		else
			@assert false "Unreachable!"
		end
	end

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		empty!(iv_times)
		empty!(iv_volts)
		empty!(iv_currs)
	end
	
	@lock gpiblock begin
		write(KeithleyIO, "SOUR:VOLT 0")
		write(KeithleyIO, "OUTP ON")
		if keithley_types[selected_keithley_type] == "MODEL 2470"
			write(KeithleyIO, "INIT")
		end
	end
	stepvals = calculate_sweep(min_volts, max_volts, step_voltage, dual)
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		voltssize = length(stepvals)
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		voltssize = ""
		@lock gpiblock voltssize = query(KeithleyIO, "SOUR:CONF:LIST:SIZE? \"VoltLinearSweepList\"")
		voltssize = parse(Int, voltssize)
	else
		@assert false "Unreachable!"
	end
	sizehint!(iv_times, voltssize)
	sizehint!(iv_volts, voltssize)
	sizehint!(iv_currs, voltssize)
	lastact = 1
	iv_is_sweeping[] = true
	if keithley_types[selected_keithley_type] == "MODEL 2400"
		for setvolts in stepvals
			iv_cancel_sweep[] && break
			set_and_measure2400(setvolts, seconds(delay), iv_cancel_sweep)			
		end
	elseif keithley_types[selected_keithley_type] == "MODEL 2470"
		while !iv_cancel_sweep[] && length(iv_volts) != voltssize
			lastact = get_outstanding_data2470(lastact)
		end
	else
		@assert false "Unreachable!"
	end
	iv_is_sweeping[] = false
	errormonitor(Threads.@spawn getevents())
end

function calculate_sweep(min_volts, max_volts, step_voltage, dual)
	if min_volts > max_volts
		min_volts, max_volts = max_volts, min_volts
	end

	firstvolts = min_volts:step_voltage:max_volts
	volts = firstvolts
	if dual
		lastvolts = max_volts:-step_voltage:min_volts
		volts = [firstvolts; lastvolts; min_volts]
	end

	volts
end

function set_and_measure2400(setvolts, sleeptime, interuptref)
	global sleep_interupt_interval
	global KeithleyIO
	global gpiblock
	@lock gpiblock write(KeithleyIO, "SOUR:VOLT $setvolts")

	interuptsleep(sleeptime, interuptref, sleep_interupt_interval)

	meascurr = measvolt = ""
	@lock gpiblock begin
		meascurr = query(KeithleyIO, "MEAS:CURR?")
		measvolt = query(KeithleyIO, "MEAS:VOLT?")
	end
	_, curr = split(meascurr, ',')
	volt, _ = split(measvolt, ',')
	measI = parse(Float64, curr)
	measV = parse(Float64, volt)

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		push!(iv_times, now())
		push!(iv_currs, measI)
		push!(iv_volts, measV)
	end
end

function get_outstanding_data2470(lastact)
	global gpiblock
	act = 0
	@lock gpiblock act = query(KeithleyIO, "TRAC:ACT?") |> x->parse(Int, x)
	lastact <= act || return lastact
	
	buff = ""
	@lock gpiblock buff = query(KeithleyIO, "TRAC:DATA? $lastact, $act")
	Imeass = split(buff, ',', keepempty=false) .|> x->parse(Float64, x)

	Vs = [
		begin
			q = ""
			@lock gpiblock q = query(KeithleyIO, "SOUR:CONF:LIST:QUER? \"VoltLinearSweepList\", $i")
			q = split(q, ',', keepempty=false)
			q = filter(q) do elem
				occursin("smu.source.level",elem)
			end[1]
			parse(Float64, split(q,'=')[2])
		end
		for i in lastact:act
	]

	global iv_times, iv_volts, iv_currs
	@lock plotlock begin
		append!(iv_times, fill(now(), size(Imeass)))
		append!(iv_volts, Vs)
		append!(iv_currs, Imeass)
	end
	return lastact+1
end