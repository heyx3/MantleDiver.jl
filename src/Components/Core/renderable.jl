"The UBO data associated with a camera"
GL.@std140 struct CameraDataBuffer
    matrix_view::fmat4x4
    matrix_projection::fmat4x4
    matrix_view_projection::fmat4x4

    matrix_inverse_view::fmat4x4
    matrix_inverse_projection::fmat4x4
    matrix_inverse_view_projection::fmat4x4

    # 3D vectors have a 4th component just to avoid padding issues.
    # It will be set to 0 or 1 as appropriate for matrix math.
    cam_pos::v4f
    cam_forward::v4f
    cam_up::v4f
    cam_right::v4f
end
function CameraDataBuffer(cam::Cam3D{Float32})
    m_view = cam_view_mat(cam)
    m_proj = cam_projection_mat(cam)
    m_view_proj = m_combine(m_view, m_proj)
    basis = cam_basis(cam)
    return CameraDataBuffer(
        m_view, m_proj, m_view_proj,
        m_invert(m_view), m_invert(m_proj), m_invert(m_view_proj),
        v4f(cam.pos..., 1),
        v4f(basis.forward..., 0),
        v4f(basis.up..., 0),
        v4f(basis.right..., 0)
    )
end
const UBO_INDEX_CAM_DATA = 3
const UBO_NAME_CAM_DATA = "CameraDataBuffer"
const UBO_CODE_CAM_DATA = """
    layout(std140, binding=$(UBO_INDEX_CAM_DATA-1)) uniform $UBO_NAME_CAM_DATA {

        $(glsl_decl(CameraDataBuffer))
    } u_world_cam;
"""


"
All inputs to a `Renderable` component.

Note that your renderables also get access to the camera data UBO;
    just inject `UBO_CODE_CAM_DATA` into your shader.
"
struct WorldRenderData
    viewport::WorldViewport
end

"
Hooks into the renderer, allowing you to draw things in the world.

All your 3D shaders should output to the standard framebuffer defined in *Renderer/framebuffer.jl*.
"
@component Renderable {abstract} begin
    @promise render(data::WorldRenderData)::Nothing
end