@concrete struct VGGFeatureExtractor <: AbstractLuxWrapperLayer{:model}
    model <: Chain
end

function VGGFeatureExtractor(config, batchnorm, inchannels)
    layers = Vector{AbstractLuxLayer}(undef, length(config) * 2)
    input_filters = inchannels
    for (i, (chs, depth)) in enumerate(config)
        layers[2i - 1] = ConvBatchNormActivation(
            (3, 3),
            input_filters => chs,
            depth,
            relu;
            last_layer_activation=true,
            conv_kwargs=(; pad=(1, 1)),
            use_norm=batchnorm,
        )
        layers[2i] = MaxPool((2, 2))
        input_filters = chs
    end
    return VGGFeatureExtractor(Chain(layers...))
end

@concrete struct VGGClassifier <: AbstractLuxWrapperLayer{:model}
    model <: Chain
end

function VGGClassifier(imsize, nclasses, fcsize, dropout)
    return VGGClassifier(
        Chain(
            FlattenLayer(),
            Dense(Int(prod(imsize)) => fcsize, relu),
            Dropout(dropout),
            Dense(fcsize => fcsize, relu),
            Dropout(dropout),
            Dense(fcsize => nclasses),
        ),
    )
end

@concrete struct VGG <: AbstractBoltzModel
    layer
    pretrained
end

"""
    VGG(imsize; config, inchannels, batchnorm = false, nclasses, fcsize, dropout)

Create a VGG model [simonyan2014very](@citep).

## Arguments

  - `imsize`: input image width and height as a tuple
  - `config`: the configuration for the convolution layers
  - `inchannels`: number of input channels
  - `batchnorm`: set to `true` to use batch normalization after each convolution
  - `nclasses`: number of output classes
  - `fcsize`: intermediate fully connected layer size
  - `dropout`: dropout level between fully connected layers
"""
function VGG(imsize; config, inchannels, batchnorm=false, nclasses, fcsize, dropout)
    feature_extractor = VGGFeatureExtractor(config, batchnorm, inchannels)
    nilarray = Lux.NilSizePropagation.NilArray((imsize..., inchannels, 2))
    outsize = LuxCore.outputsize(feature_extractor, nilarray, Random.default_rng())
    classifier = VGGClassifier(outsize, nclasses, fcsize, dropout)
    return Chain(; feature_extractor, classifier)
end

const VGG_CONFIG = Dict(
    11 => [(64, 1), (128, 1), (256, 2), (512, 2), (512, 2)],
    13 => [(64, 2), (128, 2), (256, 2), (512, 2), (512, 2)],
    16 => [(64, 2), (128, 2), (256, 3), (512, 3), (512, 3)],
    19 => [(64, 2), (128, 2), (256, 4), (512, 4), (512, 4)],
)

"""
    VGG(depth::Int; batchnorm::Bool=false, pretrained::Bool=false)

Create a VGG model [simonyan2014very](@citep) with ImageNet Configuration.

## Arguments

  - `depth::Int`: the depth of the VGG model. Choices: {`11`, `13`, `16`, `19`}.

## Keyword Arguments

  - `batchnorm = false`: set to `true` to use batch normalization after each convolution.
  - `pretrained::Bool=false`: If `true`, loads pretrained weights when `LuxCore.setup` is
    called.
"""
function VGG(depth::Int; batchnorm::Bool=false, pretrained::Bool=false)
    name = Symbol(:vgg, depth, ifelse(batchnorm, "_bn", ""))
    config, inchannels, nclasses, fcsize = VGG_CONFIG[depth], 3, 1000, 4096
    model = VGG((224, 224); config, inchannels, batchnorm, nclasses, fcsize, dropout=0.5f0)
    return VGG(model, get_vgg_pretrained_weights(name, pretrained))
end

abstract type AbstractVGGWeights <: PretrainedWeights.ArtifactsPretrainedWeight end

function get_vgg_pretrained_weights(name, pretrained::Bool)
    !pretrained && return nothing
    return get_vgg_pretrained_weights(name, :DEFAULT)
end

function get_vgg_pretrained_weights(artifact_name, name::Union{String,Symbol})
    name = Symbol(name)
    @argcheck name in (:ImageNet1K_V1, :ImageNet1K, :DEFAULT)
    name == :DEFAULT && (name = :ImageNet1K_V1)
    name == :ImageNet1K && (name = :ImageNet1K_V1)
    name == :ImageNet1K_V1 && return VGG_Weights_ImageNet1K_V1(string(artifact_name))
    return error("Unknown pretrained weights name: $(name))")
end

get_vgg_pretrained_weights(W::AbstractVGGWeights) = W

struct VGG_Weights_ImageNet1K_V1 <: AbstractVGGWeights
    artifact_name::String
end

PretrainedWeights.load_with(::Val{:JLD2}, ::VGG_Weights_ImageNet1K_V1) = true
