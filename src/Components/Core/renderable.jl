"The UBO data associated with a camera"
GL.@std140 struct CameraDataBuffer
    matrix_view::fmat4x4
    matrix_projection::fmat4x4
    matrix_view_projection::fmat4x4

    matrix_inverse_view::fmat4x4
    matrix_inverse_projection::fmat4x4
    matrix_inverse_view_projection::fmat4x4

    # 3D vectors have a 4th component just to avoid padding issues
    cam_pos::v4f
    cam_forward::v4f
    cam_right::v4f
    cam_up::v4f
end
const UBO_INDEX_CAM_DATA = 3
const UBO_NAME_CAM_DATA = "WorldCameraData"
const UBO_CODE_CAM_DATA = """
    layout(std140, binding=$(UBO_INDEX_CAM_DATA-1)) uniform $UBO_NAME_CAM_DATA {
        mat4 matrixView;
        mat4 matrixProjection;
        mat4 matrixViewProjection;

        mat4 matrixInverseView;
        mat4 matrixInverseProjection;
        mat4 matrixInverseViewProjection;

        vec4 pos;
        vec4 forward;
        vec4 right;
        vec4 up;
    } u_world_cam;
"""


"
All inputs to a `Renderable` component.
Because this struct is defined before `Mission`, that type must be fed in as a parameter.

Note that your shaders can access to the camera data UBO;
    just inject `UBO_CODE_CAM_DATA` into your shader.
"
struct WorldRenderData{TMission}
    camera::Cam3D{Float32}
    player::Entity
    framebuffer::Framebuffer
    mission::TMission
    cam_ubo_data::CameraDataBuffer
end

"
Hooks into the renderer, allowing you to draw things in the world.

All your 3D shaders should output to the standard framebuffer defined in *Renderer/framebuffer.jl*.
"
@component Renderable {abstract} begin
    @promise render(data::WorldRenderData)::Nothing
end