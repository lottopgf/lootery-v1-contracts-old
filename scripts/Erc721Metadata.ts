import z from 'zod'

export const OpenSeaTraitBasicSchema = z.object({
    trait_type: z.string().optional(),
    value: z.union([z.string(), z.number()]),
})
export type OpenSeaTraitBasic = z.TypeOf<typeof OpenSeaTraitBasicSchema>

export const OpenSeaTraitNumericSchema = z.object({
    trait_type: z.string().nullable().optional(),
    value: z.number().nullable().optional(),
    max_value: z.number().optional(),
    display_type: z.union([
        z.literal('boost_number'),
        z.literal('boost_percentage'),
        z.literal('number'),
        z.literal('date'),
    ]),
})
export type OpenSeaTraitNumericValue = z.TypeOf<typeof OpenSeaTraitNumericSchema>

export const OpenSeaTraitSchema = z.union([OpenSeaTraitBasicSchema, OpenSeaTraitNumericSchema])
export type OpenSeaTrait = z.TypeOf<typeof OpenSeaTraitSchema>

export const Erc721MetadataSchema = z.object({
    name: z.string().optional(),
    description: z.string().optional(),
    /** URI to image/video */
    image: z.string().optional(),
    /** Non-standard URI to image (used by POAP) */
    image_url: z.string().optional(),
    attributes: z.array(OpenSeaTraitSchema).optional(),
    external_url: z.string().optional(),
    /** 6-char hex without prepended # */
    background_color: z.string().optional(),
    /** OpenSea supports: gltf, glb, webm, mp4, m4v, ogv, ogg, mp3, wav, oga */
    animation_url: z.string().optional(),
    youtube_url: z.string().optional(),
})
export type Erc721Metadata = z.TypeOf<typeof Erc721MetadataSchema>
