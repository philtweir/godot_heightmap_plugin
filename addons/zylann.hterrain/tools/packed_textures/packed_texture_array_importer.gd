@tool
extends EditorImportPlugin

const HT_TextureLayeredImporter = preload("./texture_layered_importer.gd")
const HT_PackedTextureUtil = preload("./packed_texture_util.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Result = preload("../util/result.gd")
const HT_Logger = preload("../../util/logger.gd")

const IMPORTER_NAME = "hterrain_packed_texture_array_importer"
const RESOURCE_TYPE = "TextureArray"

var _logger = HT_Logger.get_for(self)


func _get_importer_name() -> String:
	return IMPORTER_NAME


func _get_visible_name() -> String:
	# This shows up next to "Import As:"
	return "HTerrainPackedTextureArray"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["packed_texarr"])


func _get_save_extension() -> String:
	return "texarr"


func _get_resource_type() -> String:
	return RESOURCE_TYPE


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return ""

func _get_import_order() -> int:
	return 0

func _get_priority() -> float:
	return 1.0

func _get_import_options(path: String, preset_index: int) -> Array:
	return [
		{
			"name": "compress/mode",
			"default_value": HT_TextureLayeredImporter.COMPRESS_VIDEO_RAM,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": HT_TextureLayeredImporter.COMPRESS_HINT_STRING
		},
		{
			"name": "flags/repeat",
			"default_value": HT_TextureLayeredImporter.REPEAT_ENABLED,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": HT_TextureLayeredImporter.REPEAT_HINT_STRING
		},
		{
			"name": "flags/filter",
			"default_value": true
		},
		{
			"name": "flags/mipmaps",
			"default_value": true
		},
		{
			"name": "flags/anisotropic",
			"default_value": false
		}
	]


func _get_option_visibility(option: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _import(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> int:

	var result := _import_real(p_source_path, p_save_path, options, r_platform_variants, r_gen_files)
	
	if not result.success:
		_logger.error(result.get_message())
		# TODO Show detailed error in a popup if result is negative
	
	var code : int = result.value
	return code


func _import_real(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> HT_Result:
	
	var f := File.new()
	var err := f.open(p_source_path, File.READ)
	if err != OK:
		return HT_Result.new(false, "Could not open file {0}: {1}" \
			.format([p_source_path, HT_Errors.get_message(err)])) \
			.with_value(err)
	var text := f.get_as_text()
	f.close()
	
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return HT_Result.new(false, "Failed to parse file {0}: {1}" \
			.format([p_source_path, json.get_error_message()])) \
			.with_value(error)
	var json_data : Dictionary = json.get_data()
	
	var resolution : int = int(json_data.resolution)
	var contains_albedo : bool = json_data.get("contains_albedo", false)
	var layers = json_data.get("layers")
	
	var images = []
	
	for layer_index in len(layers):
		var sources = layers[layer_index]
		var result = HT_PackedTextureUtil.generate_image(sources, resolution, _logger)

		if not result.success:
			return HT_Result.new(false, 
				"While importing layer {0}".format([layer_index]), result) \
				.with_value(result.value)
		
		var im : Image = result.value
		images.append(im)
	
	var result = HT_TextureLayeredImporter.import(
		p_source_path, 
		images, 
		p_save_path, 
		r_platform_variants, 
		r_gen_files, 
		contains_albedo,
		_get_visible_name(),
		options["compress/mode"],
		options["flags/repeat"],
		options["flags/filter"],
		options["flags/mipmaps"],
		options["flags/anisotropic"])
	
	if not result.success:
		return HT_Result.new(false, 
			"While importing {0}".format([p_source_path]), result) \
			.with_value(result.value)
	
	return HT_Result.new(true).with_value(OK)

