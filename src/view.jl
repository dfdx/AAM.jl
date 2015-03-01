
using Images, ImageView
using VoronoiDelaunay
import Gadfly: plot, Geom


function viewshape(img::Image, lms::Shape)
    imgc, img2 = view(img)
    for i=1:size(lms, 1)
        annotate!(imgc, img2, AnnotationPoint(lms[i, 2], lms[i, 1], shape='.',
                                              size=4, color=RGB(1, 0, 0)))
    end
end
viewshape(mat::Matrix{Float64}, lms::Shape) = viewshape(convert(Image, mat), lms)


function viewtri(img::Image, shape::Shape, trigs::Matrix{Int64})
    imgc, img2 = view(img)
    for i=1:size(trigs, 1)
        a = (shape[trigs[i, 1], 2], shape[trigs[i, 1], 1])
        b = (shape[trigs[i, 2], 2], shape[trigs[i, 2], 1])
        c = (shape[trigs[i, 3], 2], shape[trigs[i, 3], 1])
        annotate!(imgc, img2, AnnotationLine(a, b))
        annotate!(imgc, img2, AnnotationLine(b, c))
        annotate!(imgc, img2, AnnotationLine(c, a))
    end
end

viewtri(mat::Matrix{Float64}, shape::Shape, trigs::Matrix{Int64}) =
    viewtri(convert(Image, mat), shape, trigs)


histogram{T,N}(A::Array{T,N}) = plot(x=flatten(A), Geom.histogram)

function nview(img::Matrix{Float64})
    mn, mx = minimum(img), maximum(img)
    view((img - mn) / (mx - mn))
end
