import StatsBase: geomean
import Chloe.Annotator:
    annotate,
    MayBeIO,
    MayBeString,
    annotate_one_worker,
    fasta_reader,
    write_result,
    maybe_gzread,
    maybe_gzwrite,
    ChloeAnnotation,
    writeGFF3,
    writeSFF,
    CircularVector

import JSON3
# put these in the global namespace
import ..ZMQLogging: annotation_local_storage, TASK_KEY

function remove_stack!(result::ChloeAnnotation)
    for sff_model in result.annotation.forward
        for feature in sff_model.features
            feature.feature.stack = CircularVector([])
        end
    end

    for sff_model in result.annotation.reverse
        for feature in sff_model.features
            feature.feature.stack = CircularVector([])
        end
    end
    result
end

function annotate_json(db::AbstractReferenceDb, infile::String, config::ChloeConfig, outfile::String)
    result = maybe_gzread(infile) do io
        target_id, seqs = fasta_reader(io)
        annotate_one_worker(db, target_id, seqs, config)
    end
    # result = remove_stack!(result)
    io = IOBuffer()
    writeSFF(io, result.target_id, result.target_length, geomean(values(result.coverages)), result.annotation)
    sff = String(take!(io))
    io = IOBuffer()
    writeGFF3(io, result.target_id, result.target_length, result.annotation)
    gff3 = String(take!(io))
    # data = Dict("result" => result, "sff" => sff, "gff3" => gff3, "id" => result.target_id)
    data = Dict("sff" => sff, "gff3" => gff3, "id" => result.target_id)
    maybe_gzwrite(outfile) do io
        JSON3.write(io, data)
    end
    return string(result.target_id)
end

function annotate_one(db::AbstractReferenceDb, infile::String, config::ChloeConfig)
    maybe_gzread(infile) do io
        target_id, seqs = fasta_reader(io)
        return annotate_one_worker(db, target_id, seqs, config)
    end
end

function annotate_one_task(fasta::String, output::MayBeString, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    try
        annotate(select_reference(Main.REFERENCE, config.reference), fasta, config, output)
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_one_task(fasta::IO, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    try
        annotate(select_reference(Main.REFERENCE, config.reference), fasta, config, IOBuffer())
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end

function annotate_batch_task(directory::String, task_id::MayBeString, config::ChloeConfig)::Integer
    annotation_local_storage(TASK_KEY, task_id)
    nannotations = 0
    try
        db = select_reference(Main.REFERENCE, config.reference)
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

function annotate_one_task_json(fasta::String, outfile::String, task_id::MayBeString, config::ChloeConfig)
    annotation_local_storage(TASK_KEY, task_id)
    try
        annotate_json(select_reference(Main.REFERENCE, config.reference), fasta, config, outfile)
    finally
        annotation_local_storage(TASK_KEY, nothing)
    end
end
