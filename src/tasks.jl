import StatsBase: geomean
import Chloe.Annotator:
    annotate,
    MayBeIO,
    MayBeString,
    annotate_one_worker,
    fasta_reader,
    maybe_gzread,
    maybe_gzwrite,
    ChloeAnnotation,
    writeSFF,
    CircularVector,
    transform!,
    chloe2biojulia

import GenomicAnnotations: GFF, GenBank, EMBL, Record
import BioSequences: @dna_str
import JSON3
# put these in the global namespace
import ..ZMQLogging: annotation_local_storage, TASK_KEY

# see function write_result in Chloe.jl/src/output_formats.jl
function writeGFF3(io, biojulia::Record)
    GFF.printgff(io, biojulia)
end

function writeGBK(io, biojulia::Record, target_id)
    biojulia.header = "LOCUS       $(rpad(target_id, 10, ' ')) $(lpad(length(biojulia.sequence), 10, ' ')) bp    DNA     circular PLN $(uppercase(Dates.format(now(), "dd-uuu-yyyy")))"
    GeneBank.printgbk(io, biojulia)
end

function writeEMBL(io, biojulia::Record)
    EMBL.printembl(io, biojulia)
end

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
    seq_rec = maybe_gzread(infile) do io
        fasta_reader(io)
    end
    result = annotate_one_worker(db, seq_rec.target_id, seq_rec.seq, config)
    # result = remove_stack!(result)
    ts = ""
    seqs = seq_rec.seq
    if ~config.no_transform
        seqs, result, ts = transform!(seq_rec.seq, result, db.templates)
    end
    io = IOBuffer()
    writeSFF(io, result.target_id, result.target_length, geomean(values(result.coverages)), result.annotation)
    sff = String(take!(io))
    io = IOBuffer()
    biojulia = chloe2biojulia(result)
    biojulia.sequence = dna"" # seqs.forward[1:length(seqs.forward)]
    writeGFF3(io, biojulia)
    gff3 = String(take!(io))
    # data = Dict("result" => result, "sff" => sff, "gff3" => gff3, "id" => result.target_id)

    data = Dict("sff" => sff, "gff3" => gff3, "id" => result.target_id, 
    "cfg" => config, "ts" => ts)
    if ts != ""
        data["transformed"] = string(seqs.forward[1:length(seqs.forward)])
    end
    maybe_gzwrite(outfile) do io
        JSON3.write(io, data)
    end
    return string(result.target_id)
end

function annotate_one(db::AbstractReferenceDb, infile::String, config::ChloeConfig)
    seq_rec = maybe_gzread(infile) do io
        fasta_reader(io)
    end
    return annotate_one_worker(db, seq_rec.target_id, seq_rec.seq, config)
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
