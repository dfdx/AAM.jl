

using MultivariateStats


# add gloabl shape transformation parameters and orthonormalize all vectors
function global_shape_transform(s0, pc)
    npc = size(pc, 2)
    np = int(length(s0) / 2)
    # columns 1:4 - global transform params
    # columns 5:end - shape principal components
    s_star_pc = zeros(2*np, npc+4)
    s_star_pc[:, 1] = s0
    s_star_pc[1:np, 2] = -s0[np+1:end]
    s_star_pc[np+1:end, 2] = s0[1:np]
    s_star_pc[1:np, 3] = ones(np)
    s_star_pc[np+1:end, 3] = zeros(np)
    s_star_pc[1:np, 4] = zeros(np)
    s_star_pc[np+1:2*np] = ones(np)
    s_star_pc[:, 5:end] = pc
    # orthonormalizing all
    s_star_pc = gs_orthonorm(s_star_pc)
    # splitting back into global transformation params and star
    s_star, S = s_star_pc[:, 1:4], s_star_pc[:, 5:end]
    return s_star, S
end


function warp_maps(m::AAModel)
    # trigs = delaunayindexes(reshape(m.s0, int(length(m.s0) / 2), 2))
    modelh, modelw = m.frame.h, m.frame.w
    warp_map = zeros(Int, modelh, modelw)
    alpha_coords = zeros(modelh, modelw)
    beta_coords = zeros(modelh, modelw)
    for j=1:modelw
        for i=1:modelh
            for k=1:size(m.trigs, 1)
                t = m.trigs[k, :]
                i1 = m.s0[t[1]]
                j1 = m.s0[m.np + t[1]]
                i2 = m.s0[t[2]]
                j2 = m.s0[m.np + t[2]]
                i3 = m.s0[t[3]]
                j3 = m.s0[m.np + t[3]]

                den = (i2 - i1) * (j3 - j1) - (j2 - j1) * (i3 - i1)
                alpha = ((i - i1) * (j3 - j1) - (j - j1) * (i3 - i1)) / den
                beta = ((j - j1) * (i2 - i1) - (i - i1) * (j2 - j1)) / den

                if alpha >= 0 && beta >= 0 && (alpha + beta) <= 1
                    # found the triangle, save data to the bitmaps and break
                    warp_map[i, j] = k
                    alpha_coords[i, j] = alpha
                    beta_coords[i,j] = beta
                    break;
                end
            end
        end
    end
    return warp_map, alpha_coords, beta_coords
end


function init_shape_model!(m::AAModel, shapes::Vector{Shape})
    m.np = size(shapes[1], 1)
    m.trigs = delaunayindexes(shapes[1])    
    mean_shape, shapes_aligned = align_shapes(shapes)
    mini, minj = minimum(mean_shape[:, 1]), minimum(mean_shape[:, 2])
    maxi, maxj = maximum(mean_shape[:, 1]), maximum(mean_shape[:, 2])
    mean_shape[:, 1] = mean_shape[:, 1] .- (mini - 2)
    mean_shape[:, 2] = mean_shape[:, 2] .- (minj - 2)    
    m.frame = ModelFrame(int(mini), int(minj), int(maxi), int(maxj))
    shape_mat = datamatrix(Shape[shape .- mean_shape for shape in shapes_aligned])
    shape_pca = fit(PCA, shape_mat)
    pc = projection(shape_pca)
    # base shape, global transform shape and transformation matrix
    m.s0 = flatten(mean_shape)
    m.s_star, m.S = global_shape_transform(m.s0, pc)
    # precomputed helpers
    m.warp_map, m.alpha_coords, m.beta_coords = warp_maps(m)
end


function init_app_model!(m::AAModel, imgs::Vector{Matrix{Float64}}, shapes::Vector{Shape})
    app_mat = zeros(m.frame.h * m.frame.w, length(imgs))
    # trigs = delaunayindexes(shapes[1])
    for i=1:length(imgs)
        warped = warp(imgs[i], shapes[i], reshape(m.s0, m.np, 2), m.trigs)
        warped_frame = warped[1:m.frame.h, 1:m.frame.w]
        app_mat[:, i] = flatten(warped_frame)
    end
    m.A0 = squeeze(mean(app_mat, 2), 2)
    m.A = projection(fit(PCA, app_mat .- m.A0))
    di, dj = gradient2d(reshape(m.A0, m.frame.h, m.frame.w), m.warp_map)
    m.dA0 = Grad2D(di, dj)
end


function warp_jacobian(m::AAModel)
    # jacobians have form (i, j, axis, param_index)
    dW_dp = zeros(m.frame.h, m.frame.w, 2, size(m.S, 2))
    dN_dq = zeros(m.frame.h, m.frame.w, 2, 4)
    for j=1:m.frame.w
        for i=1:m.frame.h
            if m.warp_map[i, j] != 0
                t = m.trigs[m.warp_map[i, j], :]
                # for each vertex
                for k=1:3
                    dik_dp = m.S[t[k], :]
                    djk_dp = m.S[t[k]+m.np, :]

                    dik_dq = m.s_star[t[k], :]
                    djk_dq = m.s_star[t[k]+m.np, :]

                    t2 = copy(t)
                    t2[1] = t[k]
                    t2[k] = t[1]

                    # vertices of the triangle in the mean shape
                    i1 = m.s0[t2[1]]
                    j1 = m.s0[m.np + t2[1]]
                    i2 = m.s0[t2[2]]
                    j2 = m.s0[m.np + t2[2]]
                    i3 = m.s0[t2[3]]
                    j3 = m.s0[m.np + t2[3]]

                    # compute the two barycentric coordinates
                    den = (i2 - i1) * (j3 - j1) - (j2 - j1) * (i3 - i1)
                    alpha = ((i - i1) * (j3 - j1) - (j - j1) * (i3 - i1)) / den
                    beta = ((j - j1) * (i2 - i1) - (i - i1) * (j2 - j1)) / den

                    dW_dij = 1 - alpha - beta

                    dW_dp[i,j,:,:] = squeeze(dW_dp[i,j,:,:], (1, 2)) + dW_dij * [dik_dp; djk_dp]
                    dN_dq[i,j,:,:] = squeeze(dN_dq[i,j,:,:], (1, 2)) + dW_dij * [dik_dq; djk_dq]
                end
            end
        end
    end
    return dW_dp, dN_dq
end


function sd_images(m)
    app_modes = reshape(m.A, m.frame.h, m.frame.w, size(m.A, 2))
    SD = zeros(m.frame.h, m.frame.w, 4 + size(m.dW_dp, 4))
    # SD images for 4 global transformation parameters
    for i=1:4
        prj_diff = zeros(size(m.A, 2))
        for j=1:size(m.A, 2)
            prj_diff[j] = sum(app_modes[:,:,j] .* (m.dA0.di .* m.dN_dq[:,:,1,i] +
                                                   m.dA0.dj .* m.dN_dq[:,:,2,i]))
        end
        SD[:,:,i] = m.dA0.di .* m.dN_dq[:,:,1,i] + m.dA0.dj .* m.dN_dq[:,:,2,i]
        for j=1:size(m.A, 2)
            SD[:,:,i] = SD[:,:,i] - prj_diff[j] * app_modes[:,:,j]
        end
    end
    # SD images for shape parameters
    for i=1:size(m.dW_dp, 4)
        prj_diff = zeros(size(m.A, 2))
        for j=1:size(m.A, 2)
            prj_diff[j] = sum(app_modes[:,:,j] .* (m.dA0.di .* m.dW_dp[:,:,1,i] +
                                                   m.dA0.dj .* m.dW_dp[:,:,2,i]))
        end
        SD[:,:,i+4] = m.dA0.di .* m.dW_dp[:,:,1,i] + m.dA0.dj .* m.dW_dp[:,:,2,i]
        for j=1:size(m.A, 2)
            SD[:,:,i+4] = SD[:,:,i+4] - prj_diff[j] * app_modes[:,:,j]
        end
    end
    SDf = zeros(size(SD, 3), size(m.A,1))
    for i=1:size(SD, 3)
        SDf[i, :] = flatten(SD[:, :, i])
    end
    return SDf
end


function train(m::AAModel, imgs::Vector{Matrix{Float64}}, shapes::Vector{Shape})
    @assert length(imgs) == length(shapes) "Different number of images and landmark sets"
    @assert(0 <= minimum(imgs[1]) && maximum(imgs[1]) <= 1,
            "Images should be in Float64 format with values in [0..1]")
    init_shape_model!(m, shapes)
    init_app_model!(m, imgs, shapes)
    m.dW_dp, m.dN_dq = warp_jacobian(m)
    m.SD = sd_images(m)
    m.H = m.SD * m.SD'
    m.invH = inv(m.H)
    m.R = m.invH * m.SD
    return m
end



function test_train()
    imgs = read_images(IMG_DIR, 1000)
    shapes = read_landmarks(LM_DIR, 1000)
    m = AAModel()
    m = train(m, imgs, shapes)
end
