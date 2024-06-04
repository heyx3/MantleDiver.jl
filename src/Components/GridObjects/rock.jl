
##############################
#    Mineral data

# Minerals are named after the thing they're spent on.
@bp_enum(Mineral,
    storage,
    hull,
    drill,
    specials,
    sensors,
    maneuvers
)
const N_MINERALS = length(Mineral.instances())

"Some per-mineral data, stored in an immutable array"
const PerMineral{T} = Vec{N_MINERALS, T}
@inline getindex(pm::PerMineral, m::E_Mineral) = pm[Int32(m)]

"Per-rock data, stored in a bulk grid entity"
struct Rock
    minerals::PerMineral{Float32}
end


##############################
#   Bulk component

@component RockBulkElements <: BulkElements{Rock} begin
    is_passable(::v3i, ::Rock) = false

    CONSTRUCT() = SUPER()
end


###############################
#   Drill response

"A rock's response to being drilled"
@component RockDrillResponse <: DrillResponse {require: RockBulkElements} begin
    # Default behavior is fine for now
end


#################################
#   Debug 2D drawing

const ROCK_DEBUG_COLOR = vRGBf(93, 76, 82) / 255
const MINERAL_DEBUG_COLORS = PerMineral{vRGBf}(
    vRGBf(141, 191, 179),
    vRGBf(242, 235, 192),
    vRGBf(243, 180, 98),
    vRGBf(240, 96, 96),
    vRGBf(47, 127, 51),
    vRGBf(244, 64, 52)
) / 255
const MINERAL_MAX_DEBUG_COLOR_POINT = @f32(1)
const MINERAL_DEBUG_COLOR_DROPOFF = @f32(1.7)

"Draws the bulk of rocks"
@component DebugGuiVisuals_Rocks <: DebugGuiVisuals {require: RockBulkElements} begin
    bulk::RockBulkElements
    function CONSTRUCT()
        SUPER()
        this.bulk = get_component(entity, RockBulkElements)
    end
    draw_order() = typemin(Int64)
    function visualize(data::DebugGuiRenderData)
        for voxel_pos_2D::v2i in grid_idx(min_inclusive(data.world_voxel_range)):grid_idx(max_inclusive(data.world_voxel_range))
            voxel_pos::v3i =
                if data.horizontal_axis == 1
                    v3i(voxel_pos_2D.x, data.horizontal_depth, voxel_pos_2D.y)
                elseif data.horizontal_axis == 2
                    v3i(data.horizontal_depth, voxel_pos_2D.x, voxel_pos_2D.y)
                else
                    error(data.horizontal_axis)
                end
            if voxel_pos[data.other_horizontal_axis] == data.horizontal_depth
                world_rect = Box3Df(center=voxel_pos, size=one(v3f))
                gui_rect = world_to_gui(world_rect, data)
                rock = bulk_data_at(this.bulk, voxel_pos)
                if isnothing(rock)
                    continue
                end

                color::vRGBf = ROCK_DEBUG_COLOR
                for (mineral_color, mineral_strength) in zip(MINERAL_DEBUG_COLORS, rock.minerals)
                    color_strength = saturate(mineral_strength / MINERAL_MAX_DEBUG_COLOR_POINT)
                    color_strength ^= MINERAL_DEBUG_COLOR_DROPOFF
                    color = lerp(color, mineral_color, color_strength)
                end

                CImGui.ImDrawList_AddRectFilled(
                    data.draw_list,
                    min_inclusive(gui_rect).xy,
                    max_inclusive(gui_rect).xy,
                    CImGui.ImVec4(color..., 1),
                    @f32(4),
                    CImGui.LibCImGui.ImDrawFlags_None
                )
            end
        end
    end
end


#####################################
#   3D rendering

@bp_check(N_MINERALS == 6,
          "Have to tweak 'RockDataBufferElement' to fit $N_MINERALS mineral types instead of 6")

"Representation of a single rock's data in a UBO"
GL.@std140 struct RockDataBufferElement
    world_grid_pos::v4i # Fourth value is for padding
    packed_densities::v2u # Each density value is a normalizied ubyte
end
const UBO_CODE_ROCK_DATA_ELEMENT = """
    struct RockDataBufferElement {
        $(glsl_decl(RockDataBufferElement))
    };

    //Unpacks the densities of each mineral,
    //    then calculates an extra density for the plain rock
    //    so that the total density is 1.0.
    void unpackRockDensities(uvec2 packedData, out float unpackedData[$(N_MINERALS + 1)]) {
        #define UNPACK_DENSITY(i, component, shift) unpackedData[i] = float((packedData.component >> shift) & 0x000000ff) / 255.0;
        UNPACK_DENSITY(0, x, 24);
        UNPACK_DENSITY(1, x, 16);
        UNPACK_DENSITY(2, x, 8);
        UNPACK_DENSITY(3, x, 0);
        UNPACK_DENSITY(4, y, 24);
        UNPACK_DENSITY(5, y, 16);
        unpackedData[6] = 1.0 - (
            unpackedData[0] + unpackedData[1] +
            unpackedData[2] + unpackedData[3] +
            unpackedData[4] + unpackedData[5]
        );
    }
"""
@inline normalize_float_as_uint(f::AbstractFloat, U) = convert(U, round(clamp(f * typemax(U), 0, typemax(U))))
function pack_rock_densities_for_gpu(d::PerMineral{<:AbstractFloat})
    d_normalized_uint = normalize_float_as_uint.(d.data, Ref(UInt8))
    d_normalized_uint_full = convert.(Ref(UInt32), d_normalized_uint)
    return v2u(
        (d_normalized_uint_full[1] << 24) |
          (d_normalized_uint_full[2] << 16) |
          (d_normalized_uint_full[3] << 8) |
          (d_normalized_uint_full[4] << 0),
        (d_normalized_uint_full[5] << 24) |
          (d_normalized_uint_full[6] << 16)
    )
end


# Rock render data is stored in chunks, whose resolution is chosen based on GPU memory size
#    unrelated to ECS world chunk size.
const ROCK_BUFFER_CHUNK_SIZE = v3i(8, 8, 8)
const ROCK_BUFFER_CHUNK_LENGTH = prod(ROCK_BUFFER_CHUNK_SIZE)
const ROCK_BUFFER_CHUNK_BYTE_SIZE = ROCK_BUFFER_CHUNK_LENGTH * block_byte_size(RockDataBufferElement)
const INFORMED_ROCK_BUFFER_SIZE_YET = Ref(false)


GL.@std140 struct RockDataChunk
    count::UInt32
    elements::GL.StaticBlockArray{prod(ROCK_BUFFER_CHUNK_SIZE), RockDataBufferElement}
end
const UBO_INDEX_ROCK_DATA = 4
const UBO_NAME_ROCK_DATA = "RockDataChunk"
const UBO_CODE_ROCK_DATA = """
    $UBO_CODE_ROCK_DATA_ELEMENT
    layout(std140, binding=$(UBO_INDEX_ROCK_DATA - 1)) uniform $UBO_NAME_ROCK_DATA {
        $(glsl_decl(RockDataChunk))
    } u_rock_chunk;
"""

const SHADER_CODE_ROCK_COLORING = """
    MaterialSurface getRockMaterial(vec3 worldPos, vec2 uv, vec3 normal, RockDataBufferElement data) {
        //Get the density of each mineral.
        float mineralDensities[$(N_MINERALS + 1)];
        unpackRockDensities(data.packed_densities, mineralDensities);

        //Define the surface properties of each mineral, and plain rock.
        MaterialSurface mineralSurfaces[$(N_MINERALS + 1)];
        #define MINERAL(idx, foreCol, foreShape, foreDen, backCol, backDen) { \\
            mineralSurfaces[idx].foregroundColor = foreCol; \\
            mineralSurfaces[idx].foregroundDensity = foreDen; \\
            mineralSurfaces[idx].foregroundShape = foreShape; \\
            mineralSurfaces[idx].backgroundColor = backCol; \\
            mineralSurfaces[idx].backgroundDensity = backDen; \\
        }
        MINERAL($(Int(Mineral.storage)),
                6, $(Int(CharShapeType.block)), 0.3,
                6, 0.1);
        MINERAL($(Int(Mineral.hull)),
                2, $(Int(CharShapeType.block)), 0.7,
                6, 0.1);
        MINERAL($(Int(Mineral.drill)),
                6, $(Int(CharShapeType.unusual)), 0.2,
                1, 0.3);
        MINERAL($(Int(Mineral.specials)),
                7, $(Int(CharShapeType.unusual)), 0.8,
                1, 0.0);
        MINERAL($(Int(Mineral.sensors)),
                4, $(Int(CharShapeType.tall)), 0.75,
                1, 0.0);
        MINERAL($(Int(Mineral.maneuvers)),
                4, $(Int(CharShapeType.wide)), 0.275,
                1, 0.0);
        MINERAL($N_MINERALS,
                1, $(Int(CharShapeType.round)), 0.0,
                1, 0.0);

        //Pick the surface data of the densest mineral in this rock.
        //TODO: Pick a mineral in a more interesting way.
        int densestI = 0;
        for (int i = 1; i < $N_MINERALS + 1; ++i)
            if (mineralDensities[i] > mineralDensities[densestI])
                densestI = i;
        return mineralSurfaces[densestI];
    }
"""


"Gets the rock render chunk covering a given grid postion"
function rock_render_chunk_idx(world_grid_pos::Vec3)::v3i
    i = grid_idx(world_grid_pos) # If continuous, turn into voxel
    return vselect(
        i ÷ ROCK_BUFFER_CHUNK_SIZE,
        (i - ROCK_BUFFER_CHUNK_SIZE + Int32(1)) ÷ ROCK_BUFFER_CHUNK_SIZE,
        i < 0
    )
end


"Renders all rocks for the rock bulk element"
@component Renderable_Rock <: Renderable {require: RockBulkElements} begin
    bulk::RockBulkElements
    shader::Program

    # The rock data is split into chunks.
    rock_data_buffers::Dict{v3i, Tuple{RockDataChunk, GL.Buffer}}
    chunks_that_need_reupload::Set{v3i}
    rock_index_in_chunk::Dict{v3i, UInt16}


    CONSTRUCT() = begin
        SUPER()

        max_ubo_size::Int = GL.get_context().device.max_uniform_block_byte_size
        @bp_check(ROCK_BUFFER_CHUNK_BYTE_SIZE <= max_ubo_size,
                    "Rock chunk UBO size is ", ROCK_BUFFER_CHUNK_BYTE_SIZE,
                    " but this device limits UBO size to ",
                    max_ubo_size)
        @d8_debug begin
            if !INFORMED_ROCK_BUFFER_SIZE_YET[]
                INFORMED_ROCK_BUFFER_SIZE_YET[] = true
                @info "Rock chunk UBO size: $ROCK_BUFFER_CHUNK_BYTE_SIZE / $max_ubo_size == " *
                        "$(Int(round(100 * ROCK_BUFFER_CHUNK_BYTE_SIZE / max_ubo_size)))% of device limit"
            end
        end

        this.bulk = get_component(entity, RockBulkElements)
        this.rock_data_buffers = Dict{v3i, Tuple{RockDataChunk, GL.Buffer}}()
        this.chunks_that_need_reupload = Set{v3i}()
        this.rock_index_in_chunk = Dict{v3i, UInt16}()

        # Update rendering data when elements are added/removed.
        push!(this.bulk.on_element_added, (args...) -> rock_render_create(this, args...))
        push!(this.bulk.on_element_removed, (args...) -> rock_render_destroy(this, args...))

        open(io -> (this.shader = GL.bp_glsl_str("""
            $UBO_CODE_ROCK_DATA
            #START_VERTEX
                void main() { gl_Position = vec4(0, 0, 0, 1); }

            #START_GEOMETRY
                layout (points) in;
                layout(triangle_strip, max_vertices = 36) out;

                $UBO_CODE_CAM_DATA

                out vec3 fIn_worldPos;
                out vec2 fIn_uv;
                out flat vec3 fIn_normal;

                void main() {
                    if (gl_PrimitiveIDIn >= u_rock_chunk.count)
                        return;
                    gl_PrimitiveID = gl_PrimitiveIDIn; //Needed for frag shader to use it
                    RockDataBufferElement rock = u_rock_chunk.elements[gl_PrimitiveIDIn];

                    //Cube positions are centered around the grid cell.
                    //Remember that cell centers are at integer coordinates.
                    vec3 center = vec3(rock.world_grid_pos.xyz);
                    vec2 offset = vec2(-0.5, 0.5);

                    #define VERT(offsetSwizzle, uv, normal) { \\
                        fIn_worldPos = center + offset.offsetSwizzle; \\
                        fIn_uv = vec2 uv; \\
                        fIn_normal = vec3 normal; \\
                        gl_Position = u_world_cam.matrix_view_projection * vec4(fIn_worldPos, 1); \\
                        EmitVertex(); \\
                    }
                    #define FACE(normal, swizzleMinUV, swizzleMaxUMinV, swizzleMinUMaxV, swizzleMaxUV) { \\
                        VERT(swizzleMinUV   , (0, 0), normal); \\
                        VERT(swizzleMaxUMinV, (1, 0), normal); \\
                        VERT(swizzleMinUMaxV, (0, 1), normal); \\
                        VERT(swizzleMaxUV   , (1, 1), normal); \\
                        EndPrimitive(); \\
                    }
                    FACE((-1, 0,  0), rrr, rgr, rrg, rgg)
                    FACE(( 1, 0,  0), grr, ggr, grg, ggg)
                    FACE((0, -1,  0), rrr, grr, rrg, grg)
                    FACE((0,  1,  0), rgr, ggr, rgg, ggg)
                    FACE((0,  0, -1), rrr, grr, rgr, ggr)
                    FACE((0,  0,  1), rrg, grg, rgg, ggg)
                }

            #START_FRAGMENT
                in vec3 fIn_worldPos;
                in vec2 fIn_uv;
                in flat vec3 fIn_normal;

                $UBO_CODE_FRAMEBUFFER_WRITE_DATA
                $SHADER_CODE_ROCK_COLORING

                void main() {
                    RockDataBufferElement rock = u_rock_chunk.elements[gl_PrimitiveID];
                    MaterialSurface surf = getRockMaterial(fIn_worldPos, fIn_uv, fIn_normal, rock);
                    writeFramebuffer(surf);
                }
        """, debug_out=io)), "TS.frag", "w")
    end
    DESTRUCT() = begin
        close(this.shader)
        close.(gpu for (key, (cpu, gpu)) in this.rock_data_buffers)

        # Should remove the rendering lambdas, but it's hard to do correctly in practice.
        # Besides, the bulk-entity component is going to be destroyed too.
    end

    TICK() = begin
        # Upload any batched changes to chunks.
        for chunk_idx::v3i in this.chunks_that_need_reupload
            (cpu::RockDataChunk, gpu::GL.Buffer) = this.rock_data_buffers[chunk_idx]
            GL.set_buffer_data(gpu, cpu)
        end
        empty!(this.chunks_that_need_reupload)
    end

    function render(data::WorldRenderData)
        for (key, (cpu, gpu)) in this.rock_data_buffers
            GL.set_uniform_block(gpu, UBO_INDEX_ROCK_DATA)
            GL.render_mesh(
                service_BasicGraphics().empty_mesh,
                this.shader
                ;
                elements = IntervalU(
                    min=1,
                    size=cpu.count
                )
            )
        end
    end
end

function rock_render_create(renderer::Renderable_Rock, grid_pos::v3i, rock::Rock)
    chunk_idx = rock_render_chunk_idx(grid_pos)
    ubo_element = RockDataBufferElement(
        v4i(grid_pos..., 0),
        pack_rock_densities_for_gpu(rock.minerals)
    )

    local chunk::RockDataChunk,
          chunk_ubo::Buffer
    if !haskey(renderer.rock_data_buffers, chunk_idx)
        # Create a new chunk holding this single rock.
        chunk = RockDataChunk(1, ntuple(Val(ROCK_BUFFER_CHUNK_LENGTH)) do i
            if i == 1
                return ubo_element
            else
                return RockDataBufferElement(zero(v4i), zero(v2u))
            end
        end)
        chunk_ubo = Buffer(true, chunk)
    else
        # Add a new rock to the chunk.
        (chunk, chunk_ubo) = renderer.rock_data_buffers[chunk_idx]
        chunk.count += 1
        chunk.elements[chunk.count] = ubo_element

        # Mark the chunk for GPU upload next tick.
        push!(renderer.chunks_that_need_reupload, chunk_idx)
    end

    renderer.rock_data_buffers[chunk_idx] = (chunk, chunk_ubo)
    renderer.rock_index_in_chunk[grid_pos] = chunk.count
end
function rock_render_destroy(renderer::Renderable_Rock, grid_pos::v3i, rock::Rock)
    chunk_idx = rock_render_chunk_idx(grid_pos)

    # Get data about this rock and its chunk.
    @d8_assert(haskey(renderer.rock_data_buffers, chunk_idx))
    @d8_assert(haskey(renderer.rock_index_in_chunk, grid_pos))
    (chunk, chunk_ubo) = renderer.rock_data_buffers[chunk_idx]
    rock_idx = renderer.rock_index_in_chunk[grid_pos]

    # Delete the rock from the chunk.
    chunk.elements[rock_idx : chunk.count-1] = chunk.elements[rock_idx+1 : chunk.count]
    chunk.count -= 1
    delete!(renderer.rock_index_in_chunk, grid_pos)

    # Update or destroy the chunk itself.
    if chunk.count > 0
        renderer.rock_data_buffers[chunk_idx] = (chunk, chunk_ubo)
        push!(renderer.chunks_that_need_reupload, chunk_idx)
    else
        close(chunk_ubo)
        delete!(renderer.rock_data_buffers, chunk_idx)
        delete!(renderer.chunks_that_need_reupload, chunk_idx)
    end
end