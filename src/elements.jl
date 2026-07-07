

function menubar()
	if ig.BeginMenuBar()
		if ig.BeginMenu("Device Selection")
			@cstatic instrs = String[] selected_keithley::Cint = 0 begin
				if ig.Button("Refresh Devices")
					global RM
					RM = ResourceManager()
					instrs = find_resources(RM)
				end
				global selected_keithley_type
				@c ig.Combo("Keithley", &selected_keithley, instrs)
				@c ig.Combo("Type", &selected_keithley_type, keithley_types)
				global RM
				global KeithleyIO
				if ig.Button("Connect")
					connect!(RM, KeithleyIO, instrs[selected_keithley+1])
				end
				if KeithleyIO.connected
					ig.SameLine()
					ig.Text("Success!")
				else
					if !KeithleyIO.connected
						ig.SameLine()
						ig.Text("Failed to connect Keithley")
					end
				end
			end
			ig.EndMenu()
		end

		if ig.BeginMenu("Timestamp Export Mode")
			global timestamp_mode
			selected::Int32 = @match timestamp_mode begin
				:datetime => 1
				:seconds => 2
				:nanoseconds => 3
				_ => -1
			end

			@c ig.RadioButton("DateTime Timestamps", &selected, 1)
			@c ig.RadioButton("Seconds since start of capture", &selected, 2)
			@c ig.RadioButton("Nanoseconds since start of capture", &selected, 3)

			global timestamp_mode
			timestamp_mode = [:datetime, :seconds, :nanoseconds][selected]
			ig.EndMenu()
		end


		ig.EndMenuBar()
	end
end


function ivtab()
	ivinputs()
	ig.SameLine()
	ig.BeginGroup()
	flagschecks()
	simpleimplot(
		"I-V Sweep",
		"Voltage [V]", "Current [A]",
		ig.ImVec2(-sidebarwidth,-1),
		iv_volts, iv_currs
	)
	ig.EndGroup()
end

function ivinputs()
	ig.BeginGroup()
	global WINSCALE
	global can_save
	if ig.Button("Clear Data", (250WINSCALE, 30WINSCALE))
		ig.OpenPopup("clear data popup")
	end
	if ig.BeginPopup("clear data popup")
		ig.SeparatorText("Are you sure you want to erase the data?")
		ig.SeparatorText("")
		if ig.Button("I'm sure I want to permanently erase data.")
			empty!(iv_times)
			empty!(iv_currs)
			empty!(iv_volts)
			ig.CloseCurrentPopup()
		end
		ig.EndPopup()
	end
	ig.EndGroup()
end

function rttab()
	rtinputs()
	ig.SameLine()
	ig.BeginGroup()
	flagschecks()
	simpleimplot(
		"Real Time Monitor",
		"Time [s]", "Current [A]",
		ig.ImVec2(-sidebarwidth,-1),
		rt_times, rt_currs
	)
	ig.EndGroup()
end

function rtinputs()
	ig.BeginGroup()
	ig.EndGroup()
end

function flagschecks()
	global xflags
	global yflags
	@c ig.CheckboxFlags("Fit X-Axis", &xflags, ImPlot.ImPlotAxisFlags_AutoFit)
	ig.SameLine()
	@c ig.CheckboxFlags("Fit Y-Axis", &yflags, ImPlot.ImPlotAxisFlags_AutoFit)
	if (xflags | yflags) & ImPlot.ImPlotAxisFlags_AutoFit != 0
		if (xflags & yflags) & ImPlot.ImPlotAxisFlags_AutoFit != 0
			xflags = xflags & ~ImPlot.ImPlotAxisFlags_RangeFit
			yflags = yflags & ~ImPlot.ImPlotAxisFlags_RangeFit
		else
			ig.SameLine()
			if xflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
				@c ig.CheckboxFlags("Range Fit", &xflags, ImPlot.ImPlotAxisFlags_RangeFit)
			elseif yflags & ImPlot.ImPlotAxisFlags_AutoFit != 0
				@c ig.CheckboxFlags("Range Fit", &yflags, ImPlot.ImPlotAxisFlags_RangeFit)
			end
		end
	end
end

function simpleimplot(title, xaxis, yaxis, plot_size, xs, ys)
	global WINSCALE
	global sidebarwidth
	if ImPlot.BeginPlot(title, xaxis, yaxis, plot_size)
		global xflags
		global yflags
		ImPlot.SetupAxes(xaxis, yaxis, xflags, yflags)
		if !isempty(xs)
			@lock plotlock begin
				ImPlot.PlotLine("data", xs, ys)
			end
		end
		ImPlot.EndPlot()
	end
end