@concrete struct VisionTransformer <: AbstractBoltzModel
    layer
    pretrained
end

function VisionTransformer(;
    imsize::Dims{2}=(256, 256),
    in_channels::Int=3,
    patch_size::Dims{2}=(16, 16),
    embed_planes::Int=768,
    depth::Int=6,
    number_heads=16,
    mlp_ratio=4.0f0,
    dropout_rate=0.1f0,
    embedding_dropout_rate=0.1f0,
    pool::Symbol=:class,
    num_classes::Int=1000,
)
    @argcheck pool in (:class, :mean)
    return Chain(
        Chain(
            PatchEmbedding(imsize, patch_size, in_channels, embed_planes),
            ClassTokens(embed_planes),
            ViPosEmbedding(embed_planes, prod(imsize .÷ patch_size) + 1),
            Dropout(embedding_dropout_rate),
            VisionTransformerEncoder(
                embed_planes, depth, number_heads; mlp_ratio, dropout_rate
            ),
            WrappedFunction(ifelse(pool === :class, x -> x[:, 1, :], second_dim_mean)),
        ),
        Chain(LayerNorm((embed_planes,); affine=true), Dense(embed_planes, num_classes)),
    )
end

#! format: off
const VIT_CONFIGS = Dict(
    :tiny     => (depth=12, embed_planes=0192, number_heads=3                    ),
    :small    => (depth=12, embed_planes=0384, number_heads=6                    ),
    :base     => (depth=12, embed_planes=0768, number_heads=12                   ),
    :large    => (depth=24, embed_planes=1024, number_heads=16                   ),
    :huge     => (depth=32, embed_planes=1280, number_heads=16                   ),
    :giant    => (depth=40, embed_planes=1408, number_heads=16, mlp_ratio=48 / 11),
    :gigantic => (depth=48, embed_planes=1664, number_heads=16, mlp_ratio=64 / 13)
)
#! format: on

"""
    VisionTransformer(name::Symbol; pretrained=false)

Creates a Vision Transformer model with the specified configuration.

## Arguments

  - `name::Symbol`: name of the Vision Transformer model to create. The following models are
    available -- `:tiny`, `:small`, `:base`, `:large`, `:huge`, `:giant`, `:gigantic`.

## Keyword Arguments

  - `pretrained::Bool=false`: If `true`, loads pretrained weights when `LuxCore.setup` is
    called.
"""
function VisionTransformer(name::Symbol; pretrained=false, kwargs...)
    @argcheck name in keys(VIT_CONFIGS)
    return VisionTransformer(
        VisionTransformer(; VIT_CONFIGS[name]..., kwargs...),
        get_vit_pretrained_weights(name, pretrained),
    )
end

const ViT = VisionTransformer

function get_vit_pretrained_weights(name::Symbol, pretrained::Bool)
    !pretrained && return nothing
    return get_vit_pretrained_weights(name, :DEFAULT)
end

function get_vit_pretrained_weights(::Symbol, name::Union{String,Symbol})
    throw("ViT pretrained weights are not yet implemented")
end
