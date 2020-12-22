using Test
using ClimateMachine
using ClimateMachine.Mesh.Grids
using ClimateMachine.Mesh.Topologies
using ClimateMachine.MPIStateArrays
using ImperoHooks
import ImperoHooks: launch_volume_gradient!, launch_interface_gradient!
using Impero, Printf, MPI, LinearAlgebra, Statistics, GaussQuadrature
include(pwd() * "/test/test_utils.jl")
include(pwd() * "/test/gradient_test_utils.jl")

ClimateMachine.init()
const ArrayType = ClimateMachine.array_type()
const mpicomm = MPI.COMM_WORLD
const FT = Float64
Ω = Circle(-1,1) × Circle(-1,1) × Circle(-1,1)
dims = ndims(Ω)

ClimateMachine.gpu_allowscalar(true)

if 2 == ndims(Ω)
    grid = DiscontinuousSpectralElementGrid(Ω, elements = (1,1), polynomialorder = (4,4), array = ArrayType)
else
    grid = DiscontinuousSpectralElementGrid(Ω, elements = (3,2,3), polynomialorder = (3,3,3), array = ArrayType)
end

x, y, z = coordinates(grid)
nrealelem = size(x)[2] # fix this later to only depend on grid intrinsically
ijksize = prod(polynomialorders(grid) .+ 1)
device = array_device(x)
dim = ndims(Ω)
N = round(Int, size(x)[1]^(1/dim)) - 1
dependencies = nothing

# Initialize State s
Q  = MPIStateArray{FT}(mpicomm, ArrayType, ijksize, nrealelem, 1)
∇Q = MPIStateArray{FT}(mpicomm, ArrayType, ijksize, nrealelem, 3)
exact_∇Q = copy(∇Q)
cartesian_∇Q = copy(∇Q) .* 0.0
##
event = launch_volume_gradient!(∇Q, Q, grid)
wait(event)

## Test Block 1: Volume Test, gradient 
a = 1
b = 1
c = 1
@. Q.realdata[:,:, 1] = a * sin(π*x) + b * sin(π*y) + c * sin(π*z)  
@. exact_∇Q.realdata[:,:, 1] = a * π*cos(π*x)
@. exact_∇Q.realdata[:,:, 2] = b * π*cos(π*y) 
@. exact_∇Q.realdata[:,:, 3] = c * π*cos(π*z)

∇!(cartesian_∇Q, Q, grid)

event = launch_volume_gradient!(∇Q, Q, grid)
wait(event)
tol = eps(1e5) 
L∞(x) = maximum(abs.(x))
println(L∞(∇Q - exact_∇Q))
@testset "Gradient Test" begin
    @test L∞(∇Q - cartesian_∇Q) < tol
end

tol = 0.68 # small element sizes with p or h refinement this will get smaller
@testset "Exact Gradient Test" begin
    @test L∞(∇Q - exact_∇Q) < tol
end

## Test Block 2: Interface Test

event = launch_interface_gradient!(∇Q, Q, grid,)
wait(event)

tol = eps(1000.0)
@testset "Gradient Interface Test" begin
    @test L∞(∇Q) < tol
end
