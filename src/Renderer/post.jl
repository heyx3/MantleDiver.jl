@std140 struct BlurKernelSample
    dest_pixel_offset::v2f
    weight::Float32
end
const UBO_NAME_BLUR_KERNEL_SAMPLE = "BlurKernelSample"
@std140 struct BlurKernel
    samples::StaticBlockArray{16, BlurKernelSample}
    n_samples::Int
end
const UBO_NAME_BLUR_KERNEL = "BlurKernel"
const UBO_INDEX_BLUR_KERNEL = 6
const UBO_CODE_BLUR_KERNEL = """
    struct $UBO_NAME_BLUR_KERNEL_SAMPLE {
        $(glsl_decl(BlurKernelSample))
    };
    layout(std140, binding=$(UBO_INDEX_BLUR_KERNEL - 1)) uniform $UBO_NAME_BLUR_KERNEL {
        $(glsl_decl(BlurKernel))
    } u_blur_kernel;
"""

"An offering of various upscale and downscale blur kernels you could use for implementing Bloom"
const BLUR_KERNELS = Dict{Symbol, BlurKernel}(
    :dual_kawase_downscale => BlurKernel(
        let a = StaticBlockArray{16, BlurKernelSample}()
            a[1] = BlurKernelSample(v2f(0, 0), 0.5)
            a[2] = BlurKernelSample(v2f(-0.5, -0.5), 0.125)
            a[3] = BlurKernelSample(v2f(0.5, -0.5), 0.125)
            a[4] = BlurKernelSample(v2f(-0.5, 0.5), 0.125)
            a[5] = BlurKernelSample(v2f(0.5, 0.5), 0.125)
            a
        end,
        5
    ),
    :dual_kawase_upscale => BlurKernel(
        let a = StaticBlockArray{16, BlurKernelSample}()
            a[1] = BlurKernelSample(v2f(-0.5, -0.5), 1/6)
            a[2] = BlurKernelSample(v2f(0.5, -0.5), 1/6)
            a[3] = BlurKernelSample(v2f(-0.5, 0.5), 1/6)
            a[4] = BlurKernelSample(v2f(0.5, 0.5), 1/6)
            a[5] = BlurKernelSample(v2f(-1, 0), 1/12)
            a[6] = BlurKernelSample(v2f(1, 0), 1/12)
            a[7] = BlurKernelSample(v2f(0, -1), 1/12)
            a[8] = BlurKernelSample(v2f(0, 1), 1/12)
            a
        end,
        8
    )
)

"
A blurring algorithm that emulates a huge blur
  by downscaling while applying a sample kernel, then upscaling while applying another sample kernel.
"
struct DualBlur
    n_iterations::Int # How many downscales/upscales there will be, halving the resolution each time
    downscale_kernel::BlurKernel
    upscale_kernel::BlurKernel
end