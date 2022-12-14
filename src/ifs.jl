module Jifs
using Distributions, Images

const LUMINANCE_BT709 = [0.2126, 0.7152, 0.0722]
const LUM_EPS = 10^-4

# From Greg Ward, A Contrast-Based Scalefactor for Luminance Display
const WARD_LD_MAX = 200  # Max luminance
const WARD_SF_NUM = 1.219 * (WARD_LD_MAX * 0.5)^0.4

const GAMMA_ENCODING = 1 / 2.2

mutable struct ImageData
    w::Int64
    h::Int64
    data::Array{Float64,3}
    ImageData(w, h) = new(w, h, zeros(h, w, 3))
end

struct QuadPlot
    transform
    rngpos::Tuple{Uniform, Uniform}

    function QuadPlot(transform, rngpos::Tuple{Uniform, Uniform})
        new(transform, rngpos)
    end
end

function uniform_quad(quad::QuadPlot)
    [rand(quad.rngpos[1]), rand(quad.rngpos[2])]
end

const Quad0 = QuadPlot(
    (pos, w, h) -> [w/2,h/2] + (pos .* [w/2,h/2]),
    (Uniform(-1, 1), Uniform(-1, 1))
)
const Quad1 = QuadPlot(
    (pos, w, h) -> pos .* [w, h],
    (Uniform(0, 1), Uniform(0, 1))
)
const Quad12 = QuadPlot(
    (pos, w, h) -> [w/2, 0] + pos .* [w/2, h],
    (Uniform(-1, 1), Uniform(0, 1))
)

function imgcolor(img::ImageData, pos::Vector{Int64})
    i = img.h - pos[2]
    j = pos[1] + 1

    img.data[i, j, :]
end

function imgcolor!(img::ImageData, pos::Vector{Int64}, rgb::Vector{Float64})
    i = img.h - pos[2]
    j = pos[1] + 1

    img.data[i, j, :] = rgb
    nothing
end

function addcolor!(img::ImageData, pos::Vector{Int64}, rgb::Vector{Float64})
    prev = imgcolor(img, pos)
    imgcolor!(img, pos, rgb .+ prev)
    nothing
end

function scalefactor709(img::ImageData, iters::Int64)::Float64
    logsum = 0.0

    for j ∈ 1:(img.w), i ∈ 1:(img.h)
        lum = sum(img.data[i, j, :] .* LUMINANCE_BT709) / iters
        logsum += log10(max.(LUM_EPS, lum))
    end

    logmean = 10.0^(logsum / (img.w * img.h))
    ((WARD_SF_NUM / (1.219 + logmean^0.4))^2.5) / WARD_LD_MAX
end

function gammapixels!(img::ImageData, iters::Int64, scalefunc = scalefactor709)
    sf = scalefunc(img, iters)
    gamma = max.((img.data .* sf) ./ (iters / 255), 0.0) .^ GAMMA_ENCODING
    pixels = min.(1, max.(0, gamma))
    img.data = pixels
    nothing
end

struct IFSMap
    apply::Function
    color::Vector
    IFSMap(apply; color = rand(3)) = new(apply, color)
end

function rand_rot(vec::Vector{Float64}, rng = Uniform(0, 2π))
    θ = rand(rng)
    [
        cos(θ) -sin(θ)
        sin(θ) cos(θ)
    ] * vec
end

function rand_affine_map(
    vec::Vector{Float64},
    matrix_rng = Uniform(-1, 1),
    tvec_rng = Uniform(-2, 2),
)
    ma = rand(matrix_rng, 2, 2)
    tv = rand(tvec_rng, 2)
    ma * vec + tv
end

function gen_affine_map(mx::Matrix, tvec::Vector; color = rand(3))::IFSMap
    IFSMap(x -> mx * x + tvec, color = color)
end

function gen_moebius_map(coefs::Vector; color = rand(3))::IFSMap
    a, b, c, d = coefs
    function moebius(x::Vector)
        z1 = complex(x[1], x[2])
        z2 = (a * z1 + b) / (c * z1 + d)
        [real(z2), imag(z2)]
    end

    IFSMap(moebius, color = color)
end

mutable struct IFS
    img::ImageData
    maps::Vector{IFSMap}
    μ::Vector{Float64}
    pos::Vector{Float64}
    lasti::Int64
    IFS(img, maps, μ = []) = new(img, maps, μ, [0.0, 0.0], -1)
end

function next!(ifs::IFS)
    n = length(ifs.maps)
    if n != length(ifs.μ)
        ifs.μ = rand(n)
    end
    sμ = sum(ifs.μ)
    sμ ≈ 1 || (ifs.μ = ifs.μ ./ sμ)

    θ = rand()
    s = 0.0
    i = 0
    while θ > s
        i += 1
        s += ifs.μ[i]
    end

    ifs.pos = ifs.maps[i].apply(ifs.pos)
    ifs.lasti = i
    nothing
end

mutable struct IFSm
    img::ImageData
    maps::Vector{IFSMap}
    μ::Function
    pos::Vector{Float64}
    lasti::Int64
    IFSm(img, maps, μ) = new(img, maps, μ, [0.0, 0.0], -1)
end

function next!(ifs::IFSm)
    n = length(ifs.maps)
    μₓ = ifs.μ(ifs.pos)

    if length(μₓ) != n
        error("μ not seems compatible with maps, ($n != $(length(μₓ)))")
    end

    sμ = sum(μₓ)
    sμ ≈ 1 || (μₓ = μₓ ./ sμ)

    θ = rand()
    s = 0.0
    i = 0
    while θ > s
        i += 1
        s += μₓ[i]
    end

    ifs.pos = ifs.maps[i].apply(ifs.pos)
    ifs.lasti = i
    nothing
end

function nextcolor(rgb::Vector{Float64}, mapcolor::Vector)::Vector{Float64}
    rgb = (rgb + mapcolor) ./ 2
end

function fitpos!(pos::Vector{Int64}, w, h)
    pos[1] = pos[1] < 0 ? 0 : (pos[1] >= w ? w - 1 : pos[1])
    pos[2] = pos[2] < 0 ? 0 : (pos[2] >= h ? h - 1 : pos[2])
    nothing
end

function cutpos(pos::Vector{Int64}, w, h)
    x, y = pos
    x < 0 || x >= w || y < 0 || y >= h
end

function painting!(ifs, iters, npoints; quad::QuadPlot = Quad1)
    for _ = 1:npoints
        ifs.pos = uniform_quad(quad) # first quadrant
        rgb = [0.0, 0.0, 0.0] # starting color
        w, h = ifs.img.w, ifs.img.h

        for _ = 1:iters
            next!(ifs)
            mapcolor = ifs.maps[ifs.lasti].color
            rgb = nextcolor(rgb, mapcolor)

            pos = ifs.pos
            pos = quad.transform(pos, w, h)
            pos = floor.(Int64, pos)

            if !cutpos(pos, w, h)
                addcolor!(ifs.img, pos, rgb)
            end
        end
    end

    nothing
end

function rgbimgarray(img::ImageData)
    w, h = img.w, img.h

    function rgbhelper(i, j)
        r, g, b = img.data[i, j, :]
        RGB(r, g, b)
    end

    [rgbhelper(i, j) for i = 1:h, j = 1:w]
end

function showifs!(ifs, iters)
    gammapixels!(ifs.img, iters)
    rgbimgarray(ifs.img)
end

############################################################
# Examples
############################################################
function sierpinski(w, h)::IFS
    maps = [
        gen_affine_map([0.5 0; 0 0.5], [0.0, 0.0], color = [0.8, 0.2, 0.2]),
        gen_affine_map([0.5 0; 0 0.5], [1.0, 0.0], color = [0.2, 0.8, 0.2]),
        gen_affine_map([0.5 0; 0 0.5], [0.0, 1.0], color = [0.2, 0.2, 0.8]),
    ]

    μ = [1 / 3, 1 / 3, 1 / 3]
    IFS(ImageData(w, h), maps, μ)
end

# Example
function barnsley_fern(w, h)::IFS
    maps = [
        gen_affine_map([0.00 0.00; 0.00 0.16], [0.00, 0.00], color = [rand(), 0.9, rand()]),
        gen_affine_map(
            [0.85 0.04; -0.04 0.85],
            [0.00, 1.60],
            color = [rand(), 0.9, rand()],
        ),
        gen_affine_map(
            [0.20 -0.26; 0.23 0.22],
            [0.00, 1.60],
            color = [rand(), 0.9, rand()],
        ),
        gen_affine_map(
            [-0.15 0.28; 0.26 0.24],
            [0.00, 0.44],
            color = [rand(), 0.9, rand()],
        ),
    ]
    μ = [0.01, 0.85, 0.07, 0.07]
    IFS(ImageData(w, h), maps, μ)
end

function misc_ex1(w, h)::IFS
    t = 1 / 3
    maps = [
        gen_affine_map([t 0; 0 t], [0, 0], color = [1, 0.1, 0.1])
        gen_affine_map([t 0; 0 t], [1, 1], color = [0.1, 1, 0.1])
        gen_affine_map([t 0; 0 t], [-1, 1], color = [0.1, 0.1, 1])
    ]

    μ = ones(3) .* t

    IFS(ImageData(w, h), maps, μ)
end

function misc_ex2(w, h)::IFS
    M = [0.382 0; 0 0.382]
    maps = [
        gen_affine_map(M, [0.0, 0.0]),
        gen_affine_map(M, [0.618, 0]),
        gen_affine_map(M, [0.809, 0.588]),
        gen_affine_map(M, [0.309, 0.951]),
        gen_affine_map(M, [-0.191, 0.588]),
    ]

    n = length(maps)
    IFS(ImageData(w, h), maps, ones(n) ./ n)
end
############################################################

function test_ifs!(ifs, fname; npoints = 1000, iters = 10000, quad = Quad1)
    painting!(ifs, iters, npoints, quad = quad)
    println("painted")
    img = showifs!(ifs, iters)
    println("gamma correction applied")
    save(fname, img)
    println("saved as $fname")
    nothing
end

function test_sierpinski()
    ifs = sierpinski(512, 512)
    test_ifs!(ifs, "sierpinski.png")
end

function test_fern()
    ifs = barnsley_fern(1024, 512)
    test_ifs!(ifs, "fern.png", quad = Quad12)
end

function test_axis()
    halfmap = Jifs.IFSMap(x -> x ./ 2, color = [1.0, 0.0, 0.0])
    img = Jifs.ImageData(50, 50)
    ifs = Jifs.IFS(img, [halfmap], [1])
    test_ifs!(ifs, "axisQ0.png",
              npoints=100,
              iters=1000,
              quad=Quad0)

    img = Jifs.ImageData(50, 50)
    ifs = Jifs.IFS(img, [halfmap], [1])
    test_ifs!(ifs, "axisQ1.png",
              npoints=100,
              iters=1000,
              quad=Quad1)

    img = Jifs.ImageData(50, 50)
    ifs = Jifs.IFS(img, [halfmap], [1])
    test_ifs!(ifs, "axisQ12.png",
              npoints=100,
              iters=1000,
              quad=Quad12)
end

function test_misc1()
    ifs = misc_ex1(200, 200)
    test_ifs!(ifs, "misc1.png", quad = Quad0, iters = 2500, npoints = 250)
end

function test_misc2()
    ifs = misc_ex2(1000, 1000)
    test_ifs!(ifs, "misc2.png", quad = Quad0)
end
end

# #### #
# Main #
# #### #
if abspath(PROGRAM_FILE) == @__FILE__
    Jifs.test_sierpinski()
    println("Done.")
end
