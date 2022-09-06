module Jifs
    using Distributions, Images, FileIO

    const LUMINANCE_BT709 = [0.2126, 0.7152, 0.0722]
    const LUM_EPS = 10^-4

    # From Greg Ward, A Contrast-Based Scalefactor for Luminance Display
    const WARD_LD_MAX = 200  # Max luminance
    const WARD_SF_NUM = 1.219 * (WARD_LD_MAX * 0.5) ^ 0.4

    const GAMMA_ENCODING = 1 / 2.2

    mutable struct ImageData
        w::Int64
        h::Int64
        data::Array{Float64, 3}
        ImageData(w, h) = new(h, w, zeros(w, h, 3))
    end

    function imgcolor(img::ImageData, pos::Vector{Int64})
        x = pos[1] + 1
        y = img.h - pos[2]

        img.data[x, y, :]
    end

    function imgcolor!(img::ImageData, pos::Vector{Int64}, rgb::Vector{Float64})
        x = pos[1] + 1
        y = img.h - pos[2]

        img.data[x, y, :] = rgb
    end

    function addcolor!(img::ImageData, pos::Vector{Int64}, rgb::Vector{Float64})
        prev = imgcolor(img, pos)
        imgcolor!(img, pos, rgb .+ prev)
    end

    function scalefactor709(img::ImageData, iters::Int64)::Float64
        logsum = 0.0

        for x ∈ 1:img.w, y ∈ 1:img.h
            lum = sum(img.data[x, y, :] .* LUMINANCE_BT709) / iters
            logsum += log10(max.(LUM_EPS, lum))
        end

        logmean = 10.0 ^ (logsum / (img.w * img.h))
        ((WARD_SF_NUM / (1.219 + logmean ^ 0.4)) ^ 2.5) / WARD_LD_MAX
    end

    function gammapixels!(img::ImageData, iters::Int64, scalefunc=scalefactor709)
        sf = scalefunc(img, iters)
        gamma = max.((img.data .* sf) ./ (iters / 255), 0.0) .^ GAMMA_ENCODING
        pixels = min.(1, max.(0, gamma))
        img.data = pixels
    end

    struct IFSMap
         apply::Function
         color::Vector
         IFSMap(apply; color=rand(3)) = new(apply, color)
    end

    function rand_rot(vec::Vector{Float64}, rng=Uniform(0, 2π))
        θ = rand(rng)
        [cos(θ) -sin(θ)
         sin(θ) cos(θ)] * vec
    end

    function rand_affine_map(vec::Vector{Float64},
                             matrix_rng=Uniform(-1, 1),
                             tvec_rng=Uniform(-2, 2))
        ma = rand(matrix_rng, 2, 2)
        tv = rand(tvec_rng, 2)
        ma * vec + tv
    end

    function gen_affine_map(mx::Matrix, tvec::Vector; color=rand(3)) :: IFSMap
        IFSMap(x -> mx * x + tvec, color=color)
    end

    function gen_moebius_map(coefs::Vector) :: IFSMap
        a, b, c, d = coefs
        function moebius(x::Vector)
            z1 = complex(x[1], x[2])
            z2 = (a*z1 + b) / (c*z1 + d)
            real(z2), imag(z2)
        end

        IFSMap(moebius)
    end

    function apply_rand_map(vec::Vector{Float64}, maps::Vector{IFSMap}, μ::Vector{Float64}=[])
        n = length(maps)
        if n != length(μ)
            μ = rand(n)
        end
        μ = μ ./ sum(μ)

        θ = rand()
        s = 0.0
        i = 0
        while θ > s
            i += 1
            s += μ[i]
        end

        vec = maps[i].apply(vec)
        (vec, μ, i)
    end

    mutable struct IFS
        img::ImageData
        maps::Vector{IFSMap}
        μ::Vector{Float64}
        pos::Vector{Float64}
        lasti::Int64
        IFS(img, maps, μ) = new(img, maps, μ, [0., 0.], -1)
    end

    function next!(ifs::IFS)::Vector{Float64}
        ifs.pos, ifs.μ, ifs.lasti = apply_rand_map(ifs.pos, ifs.maps, ifs.μ)
        ifs.pos
    end

    function nextcolor(rgb::Vector{Float64}, mapcolor::Vector)::Vector{Float64}
        (rgb + mapcolor) ./ 2
    end

    function fitpos!(pos::Vector{Int64}, w, h)
        pos[1] = pos[1] < 0 ? 0 : (pos[1] >= w ? w-1 : pos[1])
        pos[2] = pos[2] < 0 ? 0 : (pos[2] >= h ? h-1 : pos[2])
    end

    function cutpos(pos::Vector{Int64}, w, h)
        x,y = pos
        x < 0 || x >= w || y < 0 || y >= h
    end

    function painting!(ifs, iters, npoints)
        for _ in 1:npoints
            ifs.pos = rand(Uniform(0, 1), 2) # first quadrant
            rgb = [0., 0., 0.] # starting color
            w, h = ifs.img.w, ifs.img.h

            for _ in 1:iters
                next!(ifs)
                mapcolor = ifs.maps[ifs.lasti].color
                rgb = nextcolor(rgb, mapcolor)

                # not required when ifs.pos since our initial pos
                # pos = (ifs.pos .+ 1) / 2
                # pos = pos .* [w-1, h-1]
                pos = ifs.pos .* [w, h]
                pos = floor.(Int64, pos)
                # fitpos!(pos, w, h)
                #
                if !cutpos(pos, w, h)
                    addcolor!(ifs.img, pos, rgb)
                end
            end
        end
    end

    function rgbimgarray(img::ImageData)
        w, h = img.w, img.h

        function rgbhelper(x, y)
            r, g, b = imgcolor(img, [x-1, y-1])
            RGB(r, g, b)
        end

        [rgbhelper(i, j) for i in 1:h, j in 1:w]
    end

    function showifs(ifs, iters)
        gammapixels!(ifs.img, iters)
        rgbimgarray(ifs.img)
    end

    # Example
    function sierpinski(w, h)::IFS
        maps = [gen_affine_map([0.5 0; 0 0.5], [0., 0.], color=[0.8, 0.2, 0.2]),
                gen_affine_map([0.5 0; 0 0.5], [1., 0.], color=[0.2, 0.8, 0.2]),
                gen_affine_map([0.5 0; 0 0.5], [0., 1.], color=[0.2, 0.2, 0.8])]

        μ = [1/3, 1/3, 1/3]
        IFS(
            ImageData(w, h),
            maps,
            μ
        )
    end

    # Example
    function fern(w, h)::IFS
        maps = [gen_affine_map([ 0.00  0.00;  0.00 0.16], [0.00, 0.00]),
                gen_affine_map([ 0.85  0.04; -0.04 0.85], [0.00, 1.60]),
                gen_affine_map([ 0.20 -0.26;  0.23 0.22], [0.00, 1.60]),
                gen_affine_map([-0.15  0.28;  0.26 0.24], [0.00, 0.44])]
        μ = [1, 1, 1, 1] ./ 4
        IFS(
            ImageData(w, h),
            maps,
            μ
        )
    end

    # Example
    function sierpinski_pentagon()::IFS
        maps = [gen_affine_map([0.382 0.0; 0.0 0.382], [0., 0.]),
                gen_affine_map([0.382 0.0; 0.0 0.382], [0, 0.618]),
                gen_affine_map([0.382 0.0; 0.0 0.382], [0.809, 0.588]),
                gen_affine_map([0.382 0.0; 0.0 0.382], [0.309, 0.951]),
                gen_affine_map([0.382 0.0; 0.0 0.382], [-0.191, 0.588])]

        μ = [1, 1, 1, 1, 1] ./ 5
        IFS(
            ImageData(512, 512),
            maps,
            μ
        )
    end

    function test_ifs!(ifs, fname; npoints=1000, iters=10000)
        painting!(ifs, iters, npoints)
        println("painted")
        img = showifs(ifs, iters)
        println("gamma correction applied")
        save(fname, img)
        println("saved as $fname")
    end

    function test_sierpinski()
        ifs = sierpinski(512, 512)
        test_ifs!(ifs, "sierpinski.png")
    end

    function test_fern()
        ifs = fern(512, 512)
        test_ifs!(ifs, "fern.png")
    end

    function test_pentagon()
        ifs = sierpinski_pentagon()
        test_ifs!(ifs, "pentagon.png")
    end
end

# #### #
# Main #
# #### #
if abspath(PROGRAM_FILE) == @__FILE__
    Jifs.test_sierpinski()
    println("Done.")
end
