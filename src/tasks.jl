
import Chloe.Annotator:
    annotate,
    MayBeIO,
    MayBeString,
    annotate_one_worker,
    fasta_reader,
    write_result,
    maybe_gzread,
    AbstractReferenceDb,
    maybe_gzwrite
# put these in the global namespace
import ..ZMQLogging: annotation_local_storage, set_global_logger, TASK_KEY

function annotate_gff3(
    db::AbstractReferenceDb,
    infile::String,
    config::ChloeConfig,
    sfffile::String,
    gff3file::MayBeString
)
    maybe_gzread(infile) do io
        target_id, seqs = fasta_reader(io)
        result = annotate_one_worker(db, target_id, seqs, config)
        write_result(result, false, sfffile)
        if ~isnothing(gff3file)
            write_result(result, true, gff3file)
        end

        return Dict("filename" => sfffile, "gff3" => gff3file, "ncid" => string(target_id), "config" => config)
    end
end

function annotate_one_task(fasta::String, output::MayBeString, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    db = select_reference(Main.REFERENCE, config.reference)
    try
        annotate(db, fasta, config, output)
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_one_task(fasta::IO, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    db = select_reference(Main.REFERENCE, config.reference)
    try
        annotate(db, fasta, config, IOBuffer())
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_batch_task(directory::String, task_id::MayBeString, config::ChloeConfig)::Integer
    annotation_local_storage(TASK_KEY, task_id)
    nannotations = 0
    db = select_reference(Main.REFERENCE, config.reference)
    try
        for fasta in readdir(directory; join=true)
            if endswith(fasta, r"\.(fa|fna|fasta)")
                annotate(db, fasta, config, nothing)
                nannotations += 1
            end
        end
        return nannotations
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_one_task_gff3(
    fasta::String,
    sfffile::String,
    gff3file::MayBeString,
    task_id::MayBeString,
    config::ChloeConfig
)
    annotation_local_storage(TASK_KEY, task_id)
    db = select_reference(Main.REFERENCE, config.reference)
    try
        annotate_gff3(db, fasta, config, sfffile, gff3file)
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end
