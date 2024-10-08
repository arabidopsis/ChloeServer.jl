
struct BiReference
    cp::ReferenceDb
    nr::ReferenceDb
end

function create_biref()::BiReference
    BiReference(ReferenceDb("cp"), ReferenceDb("nr"))
end

function select_reference(biref::BiReference, name::AbstractString)::ReferenceDb
    if name === "nr"
        return biref.nr
    end
    return biref.cp
end
