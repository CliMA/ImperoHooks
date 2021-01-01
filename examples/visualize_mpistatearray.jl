using ImperoHooks
using ClimateMachine
using ClimateMachine.Mesh.Grids
using Impero, MPI
using Makie, GLMakie, AbstractPlotting
using ImageTransformations, Colors
using AbstractPlotting.MakieLayout
using GaussQuadrature, Random, Test
using Statistics, Printf
using ClimateMachine.MPIStateArrays
using Base.Threads, LinearAlgebra
include(pwd() * "/examples/gridhelper.jl")
##
ClimateMachine.init()
const ArrayType = ClimateMachine.array_type()
const mpicomm = MPI.COMM_WORLD
const FT = Float64
# Domain
Ω = Circle(-1,1) × Circle(-1,1) × Circle(-1,1)
# Discretization
ex, ey, ez = (2, 1, 1) 
(npx, npy, npz) = (2,2,2)
ClimateMachine.gpu_allowscalar(true)
grid = DiscontinuousSpectralElementGrid(Ω, elements = (ex, ey, ez), polynomialorder = (npx, npy, npz), array = ArrayType)
gridhelper = GridHelper(grid)
x, y, z = coordinates(grid)
xC, yC, zC = cellcenters(grid)
##
f = MPIStateArray{FT}(mpicomm, ArrayType, size(x)..., 1)
g(x,y,z) = 1 - x^2 - y^2 - z^2
@. f =  g(x,y,z)

newsize = (10, 10, 10)
nx, ny, nz = newsize
newx = range(-1,1, length = nx)
newy = range(-1,1, length = ny)
newz = range(-1,1, length = nz)
newf = zeros((nx,ny,nz))
checkf = zeros((nx,ny,nz))
tic = time()
@threads  for i in 1:nx
    for j in 1:ny
        for k in 1:nz
            location = (newx[i], newy[j], newz[k])
            newf[i,j,k] = getvalue(f, location, gridhelper)
            checkf[i,j,k] = g(location[1], location[2], location[3])
        end
    end
end
toc = time()
println("Time to interpolate is ", toc - tic)
println("The error is ", norm(newf - checkf)/ norm(checkf))
println("The maximum difference is ", maximum(abs.(newf - checkf)))
println("The largest error is at ", argmax(abs.(newf - checkf)))
errorloc = argmax(abs.(newf - checkf))
i, j, k = errorloc[1], errorloc[2], errorloc[3]
println("The largest error is at the point ",(x[i], y[j], z[k]))

##
scene, layout = layoutscene(resolution = (2500, 860))
lscene = layout[2:4, 2:4] = LScene(scene)
layout[1, 2:4] = LText(scene, "MPIStateArray", textsize = 50)

lscene2 = layout[2:4, 5:7] = LScene(scene)
layout[1, 5:7] = LText(scene, "Exact", textsize = 50)

lscene3 = layout[2:4, 8:10] = LScene(scene)
layout[1, 8:10] = LText(scene, "Difference", textsize = 50)

upperclim_slider = LSlider(scene, range = range(0, 1, length = 101), startvalue = 0.99)
upperclim_node = upperclim_slider.value
lowerclim_slider = LSlider(scene, range = range(0, 1, length = 101), startvalue = 0.01)
lowerclim_node = lowerclim_slider.value

clims = @lift((quantile(f[:], $lowerclim_node) , quantile(f[:], $upperclim_node)))
cmap_rgb = to_colormap(:balance);
volume!(lscene, -1..1, -1..1, -1..1, newf, colormap = cmap_rgb, colorrange = clims, camera = cam3d!)
volume!(lscene2, -1..1, -1..1, -1..1, checkf, colormap = cmap_rgb, colorrange = clims, camera = cam3d!)
Δf = checkf - newf
volume!(lscene3, -1..1, -1..1, -1..1, Δf, colormap = cmap_rgb, colorrange = clims, camera = cam3d!)

    lowerclim_string = @lift("lower clim quantile = " *  @sprintf("%0.2f", $lowerclim_node) * ", value = " * @sprintf("%0.1e", $clims[1]))
    upperclim_string = @lift("upper clim quantile = " *  @sprintf("%0.2f", $upperclim_node) * ", value = " * @sprintf("%0.1e", $clims[2]))
layout[2, 1] = vgrid!(
    LText(scene, lowerclim_string, width = nothing),
    lowerclim_slider,
    LText(scene, upperclim_string, width = nothing),
    upperclim_slider,
)
display(scene)

