module LogGoodies

using Dates
using DataFrames
using Logging
using Logging: BelowMinLevel, Debug, Error, Info, Warn
using LoggingExtras
import Base.CoreLogging: shouldlog, min_enabled_level, handle_message
using Printf

export FlushedLogger
export @debug, @error, @info, @warn
export Debug, Error, Info, Warn, BelowMinLevel 
export TeeLogger, global_logger, set_logger, append_default_flushed_logger
export dataframe_to_md

"""
FlushedLogger(stream=stderr, min_level=Info)
FlushedLogger(path, min_level=Info, append=false)

Always flushed logger.

Based on `Logging.SimpleLogger`.
"""
struct FlushedLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    message_limits::Dict{Any,Int}
    dateformat::String
    showmodule::Bool
    showfile::Symbol
end

function FlushedLogger(stream::IO = stderr, level = BelowMinLevel; dateformat="HH:MM:SS", showmodule=false, showfile=:short)
    @assert showfile in [:short, :full, :none]
    FlushedLogger(stream, level, Dict{Any,Int}(), dateformat, showmodule, showfile)
end

function FlushedLogger(path::AbstractString, level = BelowMinLevel, append = false; kwargs...) 
    FlushedLogger(open(path, append ? "a" : "w"), level; kwargs...)
end

shouldlog(logger::FlushedLogger, level, _module, group, id) = get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::FlushedLogger) = logger.min_level

catch_exceptions(logger::FlushedLogger) = false

function handle_message(logger::FlushedLogger, level, message, _module, group, id,
                        filepath, line; maxlog = nothing, kwargs...)
    
    if maxlog !== nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end
    buf = IOBuffer()
    iob = IOContext(buf, logger.stream)
    levelstr = uppercase(string(level))
    datestr = logger.dateformat == "" ? "" : " $(Dates.format(now(), logger.dateformat))"
    modulestr = logger.showmodule ? " $(something(_module, "nothing"))" : ""
    if logger.showfile == :none
        filestr = ""
    elseif logger.showfile == :short
        filestr = @sprintf " %s:%s"  basename(something(filepath, "nothing")) something(line, "nothing")
    else
        filestr = @sprintf " %s:%s"  something(filepath, "nothing") something(line, "nothing")
    end
    msglines = split(chomp(string(message)), '\n')

    println(iob, levelstr, datestr, modulestr, filestr, " ", msglines[1])
    for i in 2:length(msglines)
        println(iob, " ", msglines[i])
    end
    for (key, val) in kwargs
        println(iob, "   ", key, " = ", val)
    end
    write(logger.stream, take!(buf))
    flush(logger.stream)
    nothing
end

function append_default_flushed_logger(logfile = "log.txt", level = Info)
    old_logger = global_logger()
    tee_logger = TeeLogger(
        old_logger,
        FlushedLogger(logfile, level, showmodule=false, showfile=:short)
    )
    global_logger(tee_logger)

    @info "host name: $(gethostname())"
    @info "SLURM_JOB_ID: $(get(ENV, "SLURM_JOB_ID", "N/A"))"
    @info "SLURM_JOB_NAME: $(get(ENV, "SLURM_JOB_NAME", "N/A"))"
    @info "SLURM_SUBMIT_HOST: $(get(ENV, "SLURM_SUBMIT_HOST", "N/A"))"
    @info "PBS_JOBID: $(get(ENV, "PBS_JOBID", "N/A"))"
    @info "PBS_JOBDIR: $(get(ENV, "PBS_JOBDIR", "N/A"))"
end

# ============= FORMATTERS =============

# TODO: move to a dedicated package?
function dataframe_to_md(df::AbstractDataFrame)
    s = string(df)
    s = foldl(replace, [(c => "|" for c in ["│", "┼", "├", "┤"])..., "─" => "-"]; init = s) # replace UTF symbols
    s = [l * "\n" for (i, l) in enumerate(split(s, "\n")) if i != 3] |> join
    println(s)
end

end # module
