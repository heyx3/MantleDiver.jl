const GridDirection = Bplus.GL.E_CubeFaces
const GridDirections = Bplus.GL.CubeFaces

"Gets the axis of the given direction (1=X, 2=Y, 3=Z)"
function grid_axis(dir::GridDirection)::UInt8
    return if dir in (GridDirections.pos_x, GridDirections.neg_x)
        1
    elseif dir in (GridDirections.pos_y, GridDirections.neg_y)
        2
    elseif dir in (GridDirections.pos_z, GridDirections.neg_z)
        3
    else
        error(dir)
    end
end
"Gets the sign of the given direction (positive=+1, negative=-1)"
function grid_sign(dir::GridDirection)::Int8
    return if dir in (GridDirections.pos_x, GridDirections.pos_y, GridDirections.pos_z)
        1
    elseif dir in (GridDirections.neg_x, GridDirections.neg_y, GridDirections.neg_z)
        -1
    else
        error(dir)
    end
end

"Gets the grid direction indicated by the given rotation/forward vector"
function grid_dir(rot::fquat)::GridDirection
    return grid_dir(q_apply(rot, v3f(1, 0, 0)))
end
function grid_dir(forward::Vec3)::GridDirection
    axis = findmax(forward)[2]
    dir = Int8(sign(forward[axis]))
    return grid_dir(axis, dir)
end
function grid_dir(axis::Integer, dir::Signed)::GridDirection
    return (
        GridDirections.neg_x,
        GridDirections.neg_y,
        GridDirections.neg_z,
        GridDirections.pos_x,
        GridDirections.pos_y,
        GridDirections.pos_z
    )[axis + (3 * ((dir+1) ÷ 2))]
end

"Gets a vector pointing in the given direction"
function grid_vector(dir::GridDirection, ::Type{T} = Float32)::Vec{3, T} where {T}
    v = zero(Vec{3, T})
    @set! v[grid_axis(dir)] = convert(T, grid_sign(dir))
    return v
end