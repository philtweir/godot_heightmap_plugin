@tool

# TODO Godot does not have an API to make custom texture importers easier.
# So we have to re-implement the entire logic of `ResourceImporterTexture`.
# See https://github.com/godotengine/godot/issues/24381

const HT_Result = preload("../util/result.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Util = preload("../../util/util.gd")

const COMPRESS_LOSSLESS = 0
const COMPRESS_LOSSY = 1
const COMPRESS_VRAM_COMPRESSED = 2
const COMPRESS_VRAM_UNCOMPRESSED = 3
const COMPRESS_BASIS_UNIVERSAL = 5

const COMPRESS_HINT_STRING = "Lossless,Lossy,VRAM,Uncompressed"

const REPEAT_NONE = 0
const REPEAT_ENABLED = 1
const REPEAT_MIRRORED = 2

const REPEAT_HINT_STRING = "None,Enabled,Mirrored"

# CompressedTexture2D.FORMAT_VERSION, not exposed to GDScript
const CompressedTexture2D_FORMAT_VERSION = 1

# CompressedTexture2D.DataFormat, not exposed to GDScript
const CompressedTexture2D_DATA_FORMAT_IMAGE = 0
const CompressedTexture2D_DATA_FORMAT_PNG = 1
const CompressedTexture2D_DATA_FORMAT_WEBP = 2
const CompressedTexture2D_DATA_FORMAT_BASIS_UNIVERSAL = 3

# StreamTexture.FormatBits, not exposed to GDScript
const StreamTexture_FORMAT_MASK_IMAGE_FORMAT = (1 << 20) - 1
const StreamTexture_FORMAT_BIT_LOSSLESS = 1 << 20
const StreamTexture_FORMAT_BIT_LOSSY = 1 << 21
const StreamTexture_FORMAT_BIT_STREAM = 1 << 22
const StreamTexture_FORMAT_BIT_HAS_MIPMAPS = 1 << 23
const StreamTexture_FORMAT_BIT_DETECT_3D = 1 << 24
const StreamTexture_FORMAT_BIT_DETECT_SRGB = 1 << 25
const StreamTexture_FORMAT_BIT_DETECT_NORMAL = 1 << 26
const StreamTexture_FORMAT_BIT_DETECT_ROUGHNESS = 1 << 27

static func import(
	p_source_path: String, 
	image: Image, 
	p_save_path: String,
	r_platform_variants: Array, 
	r_gen_files: Array, 
	p_contains_albedo: bool,
	importer_name: String,
	p_compress_mode: int,
	p_repeat: int,
	p_filter: bool,
	p_mipmaps: bool,
	p_anisotropic: bool) -> HT_Result:

	var compress_mode := p_compress_mode
	var lossy := 0.7
	var repeat := p_repeat
	var filter := p_filter
	var mipmaps := p_mipmaps
	var anisotropic := p_anisotropic
	var srgb := 1 if p_contains_albedo else 2
	var fix_alpha_border := false
	var premult_alpha := false
	var invert_color := false
	var stream := false
	var size_limit := 0
	var hdr_as_srgb := false
	var normal := 0
	var scale := 1.0
	var force_rgbe := false
	var bptc_ldr := 0
	var detect_3d := false
	
	var p_roughness_channel := 0

	var formats_imported := []

	if size_limit > 0 and (image.get_width() > size_limit or image.get_height() > size_limit):
		#limit size
		if image.get_width() >= image.get_height():
			var new_width := size_limit
			var new_height := image.get_height() * new_width / image.get_width()

			image.resize(new_width, new_height, Image.INTERPOLATE_CUBIC)
			
		else:
			var new_height := size_limit
			var new_width := image.get_width() * new_height / image.get_height()

			image.resize(new_width, new_height, Image.INTERPOLATE_CUBIC)

		if normal == 1:
			image.normalize()

	if fix_alpha_border:
		image.fix_alpha_edges()

	if premult_alpha:
		image.premultiply_alpha()

	if invert_color:
		var height = image.get_height()
		var width = image.get_width()

		image.lock()
		for i in width:
			for j in height:
				image.set_pixel(i, j, image.get_pixel(i, j).inverted())

		image.unlock()

	var detect_srgb := srgb == 2
	var detect_normal := normal == 0
	var force_normal := normal == 1

	if compress_mode == COMPRESS_VRAM_COMPRESSED:
		#must import in all formats, 
		#in order of priority (so platform choses the best supported one. IE, etc2 over etc).
		#Android, GLES 2.x

		var ok_on_pc := false
		var is_hdr: bool = \
			(image.get_format() >= Image.FORMAT_RF and image.get_format() <= Image.FORMAT_RGBE9995)
		var is_ldr: bool = \
			(image.get_format() >= Image.FORMAT_L8 and image.get_format() <= Image.FORMAT_RGBA4444)
		var can_bptc : bool = ProjectSettings.get("rendering/textures/vram_compression/import_bptc")
		var can_s3tc : bool = ProjectSettings.get("rendering/textures/vram_compression/import_s3tc")

		if can_bptc:
#			return Result.new(false, "{0} cannot handle BPTC compression on {1}, " +
#				"because the required logic is not exposed to the script API. " +
#				"If you don't aim to export for a platform requiring BPTC, " +
#				"you can turn it off in your ProjectSettings." \
#				.format([importer_name, p_source_path])) \
#				.with_value(ERR_UNAVAILABLE)

			# Can't do this optimization because not exposed to GDScript				
#			var channels = image.get_detected_channels()
#			if is_hdr:S
#				if channels == Image.DETECTED_LA or channels == Image.DETECTED_RGBA:
#					can_bptc = false
#			elif is_ldr:
#				#handle "RGBA Only" setting
#				if bptc_ldr == 1 and channels != Image.DETECTED_LA \
#				and channels != Image.DETECTED_RGBA:
#					can_bptc = false
#
			formats_imported.push_back("bptc")

		if not can_bptc and is_hdr and not force_rgbe:
			#convert to ldr if this can't be stored hdr
			image.convert(Image.FORMAT_RGBA8)

		if can_bptc or can_s3tc:
			_save_ctex(
				image, 
				p_save_path + ".s3tc.ctex", 
				compress_mode, 
				lossy, 
				Image.COMPRESS_BPTC if can_bptc else Image.COMPRESS_S3TC, 
				mipmaps, 
				stream, 
				detect_3d, 
				detect_srgb, 
				force_rgbe, 
				detect_normal, 
				force_normal, 
				false,
				false,
				false,
				-1,
				null,
				p_roughness_channel
				)
			r_platform_variants.push_back("s3tc")
			formats_imported.push_back("s3tc")
			ok_on_pc = true

		if ProjectSettings.get("rendering/textures/vram_compression/import_etc2"):
			_save_ctex(
				image,
				p_save_path + ".etc2.ctex",
				compress_mode,
				lossy,
				Image.COMPRESS_ETC2,
				mipmaps,
				stream,
				detect_3d,
				detect_srgb,
				force_rgbe,
				detect_normal,
				force_normal,
				false,
				true,
				false,
				-1,
				null,
				p_roughness_channel)
			r_platform_variants.push_back("etc2")
			formats_imported.push_back("etc2")

		if ProjectSettings.get("rendering/textures/vram_compression/import_etc"):
			_save_ctex(
				image,
				p_save_path + ".etc.ctex",
				compress_mode,
				lossy,
				Image.COMPRESS_ETC,
				mipmaps,
				stream,
				detect_3d,
				detect_srgb,
				force_rgbe,
				detect_normal,
				force_normal,
				false,
				true,
				false,
				-1,
				null,
				p_roughness_channel)
			r_platform_variants.push_back("etc")
			formats_imported.push_back("etc")

		if not ok_on_pc:
			# TODO This warning is normally printed by `EditorNode::add_io_error`,
			# which doesn't seem to be exposed to the script API
			return HT_Result.new(false, 
				"No suitable PC VRAM compression enabled in Project Settings. " +
				"The texture {0} will not display correctly on PC.".format([p_source_path])) \
				.with_value(ERR_INVALID_PARAMETER)
	
	else:
		#import normally
		_save_ctex(
			image,
			p_save_path + ".ctex",
			compress_mode,
			lossy, 
			Image.COMPRESS_S3TC, #this is ignored,
			mipmaps,
			stream,
			detect_3d,
			detect_srgb,
			force_rgbe,
			detect_normal,
			force_normal,
			false,
			false,
			false,
			-1,
			null,
			p_roughness_channel)
	
	# TODO I have no idea what this part means, but it's not exposed to the script API either.
#	if (r_metadata) {
#		Dictionary metadata;
#		metadata["vram_texture"] = compress_mode == COMPRESS_VIDEO_RAM;
#		if (formats_imported.size()) {
#			metadata["imported_formats"] = formats_imported;
#		}
#		*r_metadata = metadata;
#	}

	return HT_Result.new(true).with_value(OK)


static func _save_ctex(
	p_image: Image, 
	p_fpath: String, 
	p_compress_mode: int, # ResourceImporterTexture.CompressMode
	p_lossy_quality: float,
	p_vram_compression: int, # Image.CompressMode
	p_mipmaps: bool, 
	p_streamable: bool, 
	p_detect_3d: bool,
	p_detect_srgb: bool,
	p_force_rgbe: bool, 
	p_detect_normal: bool,
	p_force_normal: bool,
	p_srgb_friendly: bool,
	p_force_po2_for_compressed: bool,
	p_detect_roughness: bool,
	p_limit_mipmap: int,
	p_normal,
	p_roughness_channel: int # Image.RoughnessChannel
	) -> HT_Result:

	# Need to work on a copy because we will modify it,
	# but the calling code may have to call this function multiple times
	p_image = p_image.duplicate()
	
	var f = File.new()
	var err = f.open(p_fpath, File.WRITE)
	if err != OK:
		return HT_Result.new(false, "Could not open file {0}:\n{1}" \
			.format([p_fpath, HT_Errors.get_message(err)]))

	f.store_8('G'.unicode_at(0))
	f.store_8('S'.unicode_at(0))
	f.store_8('T'.unicode_at(0)) # godot streamable texture
	f.store_8('2'.unicode_at(0))

	# var resize_to_po2 := false
	# 
	# if p_compress_mode == COMPRESS_VIDEO_RAM and p_force_po2_for_compressed \
	# and (p_mipmaps or p_texture_flags & Texture.FLAG_REPEAT):
	# 	resize_to_po2 = true
	# 	f.store_16(HT_Util.next_power_of_two(p_image.get_width()))
	# 	f.store_16(p_image.get_width())
	# 	f.store_16(HT_Util.next_power_of_two(p_image.get_height()))
	# 	f.store_16(p_image.get_height())
	# else:
	# 	f.store_16(p_image.get_width())
	# 	f.store_16(0)
	# 	f.store_16(p_image.get_height())
	# 	f.store_16(0)
	# 
	# f.store_32(p_texture_flags)

	#format version
	f.store_32(CompressedTexture2D_FORMAT_VERSION)
	#texture may be resized later, so original size must be saved first
	f.store_32(p_image.get_width())
	f.store_32(p_image.get_height())

	var flags := 0

	if p_streamable:
		flags |= StreamTexture_FORMAT_BIT_STREAM
	if p_mipmaps:
		flags |= StreamTexture_FORMAT_BIT_HAS_MIPMAPS # mipmaps bit
	if p_detect_3d:
		flags |= StreamTexture_FORMAT_BIT_DETECT_3D
	if p_detect_srgb:
		flags |= StreamTexture_FORMAT_BIT_DETECT_SRGB
	if p_detect_roughness:
		flags |= StreamTexture_FORMAT_BIT_DETECT_ROUGHNESS
	if p_detect_normal:
		flags |= StreamTexture_FORMAT_BIT_DETECT_NORMAL

	f.store_32(flags);
	f.store_32(p_limit_mipmap);
	#reserved for future use
	f.store_32(0);
	f.store_32(0);
	f.store_32(0);

	if (p_compress_mode == COMPRESS_LOSSLESS or p_compress_mode == COMPRESS_LOSSY) \
	and p_image.get_format() > Image.FORMAT_RGBA8:
		p_compress_mode = COMPRESS_VRAM_UNCOMPRESSED # these can't go as lossy

	if ((p_compress_mode == COMPRESS_BASIS_UNIVERSAL) \
	or (p_compress_mode == COMPRESS_VRAM_COMPRESSED \
	and p_force_po2_for_compressed)) and p_mipmaps:
		p_image.resize_to_po2()

	if p_mipmaps and (not p_image.has_mipmaps() or p_force_normal):
		p_image.generate_mipmaps(p_force_normal)

	if not p_mipmaps:
		p_image.clear_mipmaps()

	# RMV if p_image.has_mipmaps():
	# RMV 	p_image.generate_mipmap_roughness(p_roughness_channel, p_normal)

	var csource = Image.COMPRESS_SOURCE_GENERIC
	if p_force_normal:
		csource = Image.COMPRESS_SOURCE_NORMAL
	elif p_srgb_friendly:
		csource = Image.COMPRESS_SOURCE_SRGB

	var used_channels = p_image.detect_used_channels(csource)

	return save_to_ctex_format(f, p_image, p_compress_mode, used_channels, p_vram_compression, p_lossy_quality)

static func save_to_ctex_format(
	f: File, 
	p_image: Image, 
	p_compress_mode: int, # ResourceImporterTexture.CompressMode
	p_channels: int, # Image::UsedChannels,
	p_compress_format: int, # Image::CompressMode,
	p_lossy_quality: float,
	) -> HT_Result:

	var mmc

	match p_compress_mode:
		COMPRESS_LOSSLESS:
			var lossless_force_png: bool = false
			lossless_force_png = ProjectSettings.get_setting("rendering/textures/lossless_compression/force_png") # or \
				# not Image._webp_mem_loader_func # not sure how we can check this from GDScript
			var use_webp: bool = lossless_force_png and p_image.get_width() <= 16383 && p_image.get_height() <= 16383 # WebP has a size limit
			f.store_32(CompressedTexture2D.DATA_FORMAT_WEBP if use_webp else CompressedTexture2D.DATA_FORMAT_PNG)
			f.store_16(p_image.get_width())
			f.store_16(p_image.get_height())
			f.store_32(mmc)
			f.store_32(p_image.get_format())

			mmc = _get_required_mipmap_count(p_image)
			for i in mmc:
				var data
				if use_webp:
					return HT_Result.new(false, "WebP not implemented")
					# data = Image.webp_lossless_packer(p_image.get_image_from_mipmap(i))
					# f.store_32(data.size() + 4)
					# f.store_buffer(data)
				else:
					data = p_image.save_png_to_buffer()
					f.store_32(data.size() + 4)
					f.store_8('P'.unicode_at(0))
					f.store_8('N'.unicode_at(0))
					f.store_8('G'.unicode_at(0))
					f.store_8(' '.unicode_at(0))
					f.store_buffer(data)

		COMPRESS_LOSSY:
			return HT_Result.new(false,
				"Saving a StreamTexture with lossy compression cannot be achieved by scripts.\n"
				+ "Godot would need to either allow to save an image as WEBP to a buffer,\n"
				+ "or expose `ResourceImporterTexture::_save_ctex` so custom importers\n"
				+ "would be easier to make.")

		COMPRESS_VRAM_COMPRESSED:
			var image : Image = p_image.duplicate()
			image.compress_from_channels(p_compress_format, p_channels, p_lossy_quality)

			mmc = _get_required_mipmap_count(image)
			f.store_32(CompressedTexture2D_DATA_FORMAT_IMAGE)
			f.store_16(image.get_width())
			f.store_16(image.get_height())
			f.store_32(mmc)
			f.store_32(image.get_format())
			
			var data = image.get_data();
			f.store_buffer(data)
		
		COMPRESS_VRAM_UNCOMPRESSED:
			mmc = _get_required_mipmap_count(p_image)
			f.store_32(CompressedTexture2D_DATA_FORMAT_IMAGE)
			f.store_16(p_image.get_width())
			f.store_16(p_image.get_height())
			f.store_32(mmc)
			f.store_32(p_image.get_format())

			var data = p_image.get_data()
			f.store_buffer(data)

		COMPRESS_BASIS_UNIVERSAL:
			return HT_Result.new(false, "Basis Universal not implemented")
			# f.store_32(CompressedTexture2D.DATA_FORMAT_BASIS_UNIVERSAL)
			# f.store_16(p_image.get_width())
			# f.store_16(p_image.get_height())
			# f.store_32(p_image.get_mipmap_count())
			# f.store_32(p_image.get_format())

			# var mmc := _get_required_mipmap_count(p_image)
			# for i in mmc:
				# var data := Image.basis_universal_packer(p_image.get_image_from_mipmap(i), p_channels)
				# f.store_32(data.size())

				# f.store_buffer(data)

		_:
			return HT_Result.new(false, "Invalid compress mode specified: {0}" \
				.format([p_compress_mode]))
	
	return HT_Result.new(true)


# TODO Godot doesn't expose `Image.get_mipmap_count()`
# And the implementation involves shittons of unexposed code,
# so we have to fallback on a simplified version
static func _get_required_mipmap_count(image: Image) -> int:
	var dim: int = max(image.get_width(), image.get_height())
	return int(log(dim) / log(2) + 1)


