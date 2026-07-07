module Keithley

include("args.jl")

import CImGui as ig, ModernGL, GLFW
import CImGui.CSyntax: @c, @cstatic
import ImPlot

global plotlock = ReentrantLock()
global gpiblock = ReentrantLock()

using NativeFileDialog, DelimitedFiles

include("BetterSleep.jl")
using .BetterSleep
import .BetterSleep: now
include("save.jl")

global sleep_interupt_interval::Nano = millis(100)

using Instruments

global RM::UInt32 = ResourceManager()
global KeithleyIO::GenericInstrument = GenericInstrument()

const keithley_types = [
	"2400",
	"2470",
]
global selected_keithley_type::Cint = 0

# Can be :datetime, :seconds, or :nanoseconds
global timestamp_mode::Symbol = :seconds

# Initialize Plot Axis Flags
global xflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
global yflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit

global WINSCALE::Float32 = 1.0
global sidebarwidth = 200WINSCALE

include("elements.jl")

function (@main)(ARGS)
	global sleep_interupt_interval
	## Parse ARGS
	parsed = parse_commandline()
	if parsed["sleep_interupt_time"] !== nothing
		sleepii = parse(Int, parsed["sleep_interupt_time"])
		sleep_interupt_interval = millis(sleepii)
	end

	
	## Initialize CImGui
	ig.set_backend(:GlfwOpenGL3)

	ctx = ig.CreateContext()
	io = ig.GetIO()
	io.ConfigDpiScaleFonts = true
	io.ConfigDpiScaleViewports = true
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_DockingEnable
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_ViewportsEnable
	style = ig.GetStyle()
	p_ctx = ImPlot.CreateContext()

	## Add Icon fonts
	fonts = unsafe_load(ig.GetIO().Fonts)
	default_font = ig.AddFontDefault(fonts)
	global fontawesome = ig.AddFontFromFileTTF(fonts, joinpath(@__DIR__,"..", "fonts", "Font Awesome 7 Free-Regular-400.otf"), 16)
	@assert default_font != C_NULL
	@assert fontawesome != C_NULL

	ig.render(ctx; window_size=(100,100), window_title="Keithley 2470", on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		global WINSCALE
		global sidebarwidth
		WINSCALE = ig.GetWindowDpiScale()
		sidebarwidth = 100WINSCALE

		@cstatic first_frame = true begin
			if first_frame
				win = ig._current_window(Val{:GlfwOpenGL3}())
				GLFW.HideWindow(win)
			end
			first_frame = false
		end

		@cstatic exit_bool = true begin
			exit_bool || exit()
			@c ig.Begin("Plot Window", &exit_bool,
				ig.ImGuiWindowFlags_MenuBar |
				ig.ImGuiWindowFlags_NoCollapse )
		end

		menubar()

		if ig.BeginTabBar("IV and RealTime", ig.ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)
			if ig.BeginTabItem("I-V Sweep")
				ivtab()
			end

			if ig.BeginTabItem("Realtime Monitor")
				rttab()
			end
		end
		ig.SameLine()
		logs()

		ig.End()
	end

end


end # module Keithley
