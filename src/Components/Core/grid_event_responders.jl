
##########################
#   Drill Response

"
Grid Elements need to respond to being drilled by the player.
By default, an element always allows drilling and kills itself after being drilled.
"
@component DrillResponse {abstract} {entitySingleton} begin
    # To allow bulk entities to use this component,
    #    all methods will pass the voxel index of the thing being drilled.

    "Returns false if the player's cab cannot drill this right now"
    @configurable can_be_drilled(voxel_pos::v3i, cab::Entity)::Bool = true
    "Acknowledges the initiation of a drill action by the player cab. Defaults to doing nothing"
    @configurable start_drilling(voxel_pos::v3i, cab::Entity)::Nothing = nothing
    "Acknowledges the cancellation of an ongoing drill action by the player cab. Defaults to doing nothing"
    @configurable cancel_drilling(voxel_pos::v3i, cab::Entity)::Nothing = nothing
    "Acknowledges the completion of an ongoing drill action by the player cab. Defaults to killing this entity (or part of a bulk entity)"
    @configurable finish_drilling(voxel_pos::v3i, cab::Entity)::Nothing = begin
        bulk = get_component(entity, BulkElements)
        if exists(bulk)
            remove_bulk_entity!(get_component(world, GridManager)[1], voxel_pos)
        else
            remove_entity(world, entity)
        end
    end

    DEFAULT() = DefaultDrillResponse()
end
@component DefaultDrillResponse <: DrillResponse begin end

function get_drill_response(entity)::Optional{DrillResponse}
    if entity isa BulkEntity
        entity = entity[1].entity
    end
    return get_component(entity, DrillResponse)
end


