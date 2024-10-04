
# put these in the global namespace
import ..ZMQLogging: annotation_local_storage, set_global_logger, TASK_KEY
import ..Annotator: annotate, MayBeIO, MayBeString, ChloeConfig


#### these are only used by chloe_distributed ####

function annotate_one_task(fasta::String, output::MayBeIO, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    try
        annotate(Main.REFERENCE, fasta, config, output)
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end


function annotate_one_task(fasta::Union{String,IO}, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    try
        annotate(Main.REFERENCE, fasta, config, IOBuffer())
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_batch_task(directory::String, task_id::MayBeString, config::ChloeConfig)::Integer
    annotation_local_storage(TASK_KEY, task_id)
    nannotations = 0
    try
        for fasta in readdir(directory; join=true)
            if endswith(fasta, r"\.(fa|fasta)")
                annotate(Main.REFERENCE, fasta, config, nothing)
                nannotations += 1
            end
        end
        return nannotations
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end
