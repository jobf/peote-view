package peote.text;

#if !macro
@:genericBuild(peote.text.FontProgram.FontProgramMacro.build())
class FontProgram<T> {}
#else

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.TypeTools;

class FontProgramMacro
{
	public static var cache = new Map<String, Bool>();
	
	static public function build()
	{	
		switch (Context.getLocalType()) {
			case TInst(_, [t]):
				switch (t) {
					case TInst(n, []):
						var style = n.get();
						var styleSuperName:String = null;
						var styleSuperModule:String = null;
						var s = style;
						while (s.superClass != null) {
							s = s.superClass.t.get(); trace("->" + s.name);
							styleSuperName = s.name;
							styleSuperModule = s.module;
						}
						return buildClass(
							"FontProgram", style.pack, style.module, style.name, styleSuperModule, styleSuperName, TypeTools.toComplexType(t)
						);	
					default: Context.error("Type for GlyphStyle expected", Context.currentPos());
				}
			default: Context.error("Type for GlyphStyle expected", Context.currentPos());
		}
		return null;
	}
	
	static public function buildClass(className:String, stylePack:Array<String>, styleModule:String, styleName:String, styleSuperModule:String, styleSuperName:String, styleType:ComplexType):ComplexType
	{		
		var styleMod = styleModule.split(".").join("_");
		
		className += "__" + styleMod;
		if (styleModule.split(".").pop() != styleName) className += ((styleMod != "") ? "_" : "") + styleName;
		
		var classPackage = Context.getLocalClass().get().pack;
		
		if (!cache.exists(className))
		{
			cache[className] = true;
			
			var styleField:Array<String>;
			//if (styleSuperName == null) styleField = styleModule.split(".").concat([styleName]);
			//else styleField = styleSuperModule.split(".").concat([styleSuperName]);
			styleField = styleModule.split(".").concat([styleName]);
			
			var glyphType = Glyph.GlyphMacro.buildClass("Glyph", stylePack, styleModule, styleName, styleSuperModule, styleSuperName, styleType);
			
			#if peoteview_debug_macro
			trace('generating Class: '+classPackage.concat([className]).join('.'));	
			
			trace("ClassName:"+className);           // FontProgram__peote_text_GlypStyle
			trace("classPackage:" + classPackage);   // [peote,text]	
			
			trace("StylePackage:" + stylePack);  // [peote.text]
			trace("StyleModule:" + styleModule); // peote.text.GlyphStyle
			trace("StyleName:" + styleName);     // GlyphStyle			
			trace("StyleType:" + styleType);     // TPath(...)
			trace("StyleField:" + styleField);   // [peote,text,GlyphStyle,GlyphStyle]
			#end
			
			var glyphStyleHasMeta = Glyph.GlyphMacro.parseGlyphStyleMetas(styleModule+"."+styleName); // trace("FontProgram: glyphStyleHasMeta", glyphStyleHasMeta);
			var glyphStyleHasField = Glyph.GlyphMacro.parseGlyphStyleFields(styleModule+"."+styleName); // trace("FontProgram: glyphStyleHasField", glyphStyleHasField);
			
			var charDataType:ComplexType;
			if (glyphStyleHasMeta.packed) {
				if (glyphStyleHasMeta.multiTexture && glyphStyleHasMeta.multiSlot) charDataType = macro: {unit:Int, slot:Int, fontData:peote.text.Gl3FontData, metric:peote.text.Gl3FontData.Metric};
				else if (glyphStyleHasMeta.multiTexture) charDataType = macro: {unit:Int, fontData:peote.text.Gl3FontData, metric:peote.text.Gl3FontData.Metric};
				else if (glyphStyleHasMeta.multiSlot) charDataType = macro: {slot:Int, fontData:peote.text.Gl3FontData, metric:peote.text.Gl3FontData.Metric};
				else charDataType = macro: {fontData:peote.text.Gl3FontData, metric:peote.text.Gl3FontData.Metric};
			}
			else  {
				if (glyphStyleHasMeta.multiTexture && glyphStyleHasMeta.multiSlot) charDataType = macro: {unit:Int, slot:Int, min:Int, max:Int};
				else if (glyphStyleHasMeta.multiTexture) charDataType = macro: {unit:Int, min:Int, max:Int};
				else if (glyphStyleHasMeta.multiSlot) charDataType = macro: {slot:Int, min:Int, max:Int};
				else charDataType = macro: {min:Int, max:Int};
			}

			// -------------------------------------------------------------------------------------------
			var c = macro		

			class $className extends peote.view.Program
			{
				public var font:peote.text.Font<$styleType>; // TODO peote.text.Font<$styleType>
				public var fontStyle:$styleType;
				
				public var penX:Float = 0.0;
				public var penY:Float = 0.0;
				
				var prev_charcode = -1;
				
				var _buffer:peote.view.Buffer<$glyphType>;
				
				public function new(font:peote.text.Font<$styleType>, fontStyle:$styleType)
				{
					_buffer = new peote.view.Buffer<$glyphType>(100);
					super(_buffer);	
					
					setFont(font);
					setFontStyle(fontStyle);
				}
				
				// -----------------------------------------
				// ---------------- Font  ------------------
				// -----------------------------------------
				public inline function setFont(font:Font<$styleType>):Void
				{
					this.font = font;
					autoUpdateTextures = false;

					${switch (glyphStyleHasMeta.multiTexture) {
						case true: macro setMultiTexture(font.textureCache.textures, "TEX");
						default: macro setTexture(font.textureCache, "TEX");
					}}
				}
				
				public inline function setFontStyle(fontStyle:$styleType):Void
				{
					this.fontStyle = fontStyle;
					
					var color:String;
					${switch (glyphStyleHasField.local_color) {
						case true: macro color = "color";
						default: switch (glyphStyleHasField.color) {
							case true: macro color = Std.string(fontStyle.color.toGLSL());
							default: macro color = Std.string(font.config.color.toGLSL());
					}}}
					
					// check distancefield-rendering
					if (font.config.distancefield) {
						var weight = "0.5";
						${switch (glyphStyleHasField.local_weight) {
							case true:  macro weight = "weight";
							default: switch (glyphStyleHasField.weight) {
								case true: macro weight = peote.view.utils.Util.toFloatString(fontStyle.weight);
								default: macro {}
							}
						}}
						var sharp = peote.view.utils.Util.toFloatString(0.5); // TODO
						setColorFormula(color + " * smoothstep( "+weight+" - "+sharp+" * fwidth(TEX.r), "+weight+" + "+sharp+" * fwidth(TEX.r), TEX.r)");							
					}
					else {
						// TODO: bold for no distancefields needs some more spice inside fragmentshader (access to neightboar pixels!)

						// TODO: dirty outline
/*						injectIntoFragmentShader(
						"
							float outline(float t, float threshold, float width)
							{
								return clamp(width - abs(threshold - t) / fwidth(t), 0.0, 1.0);
							}						
						");
						//setColorFormula("mix("+color+" * TEX.r, vec4(1.0,1.0,1.0,1.0), outline(TEX.r, 1.0, 5.0))");							
						//setColorFormula("mix("+color+" * TEX.r, "+color+" , outline(TEX.r, 1.0, 2.0))");							
						//setColorFormula(color + " * mix( TEX.r, 1.0, outline(TEX.r, 0.3, 1.0*uZoom) )");							
						//setColorFormula("mix("+color+"*TEX.r, vec4(1.0,1.0,0.0,1.0), outline(TEX.r, 0.0, 1.0*uZoom) )");							
*/						
						setColorFormula(color + " * TEX.r");							
					}

					alphaEnabled = true;
					
					${switch (glyphStyleHasField.zIndex && !glyphStyleHasField.local_zIndex) {
						case true: macro setFormula("zIndex", peote.view.utils.Util.toFloatString(fontStyle.zIndex));
						default: macro {}
					}}
					
					${switch (glyphStyleHasField.rotation && !glyphStyleHasField.local_rotation) {
						case true: macro setFormula("rotation", peote.view.utils.Util.toFloatString(fontStyle.rotation));
						default: macro {}
					}}
					

					var tilt:String = "0.0";
					${switch (glyphStyleHasField.local_tilt) {
						case true:  macro tilt = "tilt";
						default: switch (glyphStyleHasField.tilt) {
							case true: macro tilt = peote.view.utils.Util.toFloatString(fontStyle.tilt);
							default: macro {}
						}
					}}
					
					
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- packed font -------
						{
							// tilting
							if (tilt != "0.0") setFormula("x", "x + (1.0-aPosition.y)*w*" + tilt);
						}
						default: macro // ------- simple font -------
						{
							// make width/height constant if global
							${switch (glyphStyleHasField.local_width) {
								case true: macro {}
								default: switch (glyphStyleHasField.width) {
									case true:
										macro setFormula("width", peote.view.utils.Util.toFloatString(fontStyle.width));
									default:
										macro setFormula("width", peote.view.utils.Util.toFloatString(font.config.width));
							}}}
							${switch (glyphStyleHasField.local_height) {
								case true: macro {}
								default: switch (glyphStyleHasField.height) {
									case true:
										macro setFormula("height", peote.view.utils.Util.toFloatString(fontStyle.height));
									default:
										macro setFormula("height", peote.view.utils.Util.toFloatString(font.config.height));
							}}}
							
							// mixing alpha while use of zIndex
							${switch (glyphStyleHasField.zIndex) {
								case true: macro {discardAtAlpha(0.5);}
								default: macro {}
							}}
							
							if (tilt != "" && tilt != "0.0") setFormula("x", "x + (1.0-aPosition.y)*width*" + tilt);
							
						}
						
					}}
					
					updateTextures();
				}
				
				// -------------------------------------------------------------------------------------------------
				// -------------------------------------------------------------------------------------------------
				// -------------------------------------------------------------------------------------------------
				
				inline function getLineMetric(glyph:$glyphType, fontData:peote.text.Gl3FontData): {asc:Float, base:Float, desc:Float}
				{
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							var height = ${switch (glyphStyleHasField.local_height) {
								case true: macro glyph.height;
								default: switch (glyphStyleHasField.height) {
									case true: macro fontStyle.height;
									default: macro font.config.height;
							}}}
							return {
								asc: height *(fontData.height + fontData.descender - (1 + fontData.ascender - fontData.height)),
								base:height *(fontData.height + fontData.descender),
								desc:height * fontData.height
							};
							
						}
						default: macro // ------- simple font -------
						{
							return null; // TODO: baseline from fontconfig!!!
						}
					}}
					
				}
				
				// returns range, fontdata and metric in dependend of font-type
				inline function getCharData(charcode:Int):$charDataType 
				{
					${switch (glyphStyleHasMeta.packed) {
						// ------- Gl3Font -------
						case true: 
							if (glyphStyleHasMeta.multiTexture && glyphStyleHasMeta.multiSlot) {
								macro {
									var range = font.getRange(charcode);
									if (range != null) {
										var metric = range.fontData.getMetric(charcode);
										if (metric == null) return null;
										else return {unit:range.unit, slot:range.slot, fontData:range.fontData, metric:metric};
									}
									else return null;
								}
							}
							else if (glyphStyleHasMeta.multiTexture) 
								macro {
									var range = font.getRange(charcode);
									if (range != null) {
										var metric = range.fontData.getMetric(charcode);
										if (metric == null) return null;
										else return {unit:range.unit, fontData:range.fontData, metric:metric};
									}
									else return null;
								}
							else if (glyphStyleHasMeta.multiSlot)
								macro {
									var range = font.getRange(charcode);
									if (range != null) {
										var metric = range.fontData.getMetric(charcode);
										if (metric == null) return null;
										else return {slot:range.slot, fontData:range.fontData, metric:metric};
									}
									else return null;
								}
							else macro {
									var metric = font.getRange(charcode).getMetric(charcode);
									if (metric == null) return null;
									else return {fontData:font.getRange(charcode), metric:metric};
								}
						// ------- simple font -------
						default:macro return font.getRange(charcode);
					}}
				}
				
				// -------------------------------------------------
				
				inline function rightGlyphPos(glyph:$glyphType, charData:$charDataType):Float
				{
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							${switch (glyphStyleHasField.local_width) {
								case true: macro return glyph.x + (charData.metric.advance - charData.metric.left) * glyph.width;
								default: switch (glyphStyleHasField.width) {
									case true: macro return glyph.x + (charData.metric.advance - charData.metric.left) * fontStyle.width;
									default: macro return glyph.x + (charData.metric.advance - charData.metric.left) * font.config.width;
							}}}
						}
						default: macro // ------- simple font -------
						{
							return glyph.x + glyph.width;
						}
					}}
				}
				
				inline function leftGlyphPos(glyph:$glyphType, charData:$charDataType):Float
				{
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							${switch (glyphStyleHasField.local_width) {
								case true: macro return glyph.x - (charData.metric.left) * glyph.width;
								default: switch (glyphStyleHasField.width) {
									case true: macro return glyph.x - (charData.metric.left) * fontStyle.width;
									default: macro return glyph.x - (charData.metric.left) * font.config.width;
							}}}
						}
						default: macro // ------- simple font -------
						{
							return glyph.x;
						}
					}}
					
				}
				
				inline function nextGlyphOffset(glyph:$glyphType, charData:$charDataType):Float
				{
					${switch (glyphStyleHasMeta.packed)
					{	case true: macro // ------- Gl3Font -------
						{
							${switch (glyphStyleHasField.local_width) {
								case true: macro return charData.metric.advance * glyph.width;
								default: switch (glyphStyleHasField.width) {
									case true: macro return charData.metric.advance * fontStyle.width;
									default: macro return charData.metric.advance * font.config.width;
							}}}
						}
						default: macro {
							return glyph.width;//TODO: - width / font.config.width * (font.config.paddingRight - font.config.paddingLeft);
						}
					}}					
				}
				
				inline function kerningOffset(prev_glyph:$glyphType, glyph:$glyphType, kerning:Array<Array<Float>>):Float
				{
					${switch (glyphStyleHasMeta.packed)
					{	case true: macro // ------- Gl3Font -------
						{	
							if (font.kerning && prev_glyph != null) 
							{	trace("kerning: ", prev_glyph.char, glyph.char, " -> " + kerning[prev_glyph.char][glyph.char]);
								${switch (glyphStyleHasField.local_width) {
									case true: macro return kerning[prev_glyph.char][glyph.char] * (glyph.width + prev_glyph.width)/2;
									default: switch (glyphStyleHasField.width) {
										case true: macro return kerning[prev_glyph.char][glyph.char] * fontStyle.width;
										default: macro return kerning[prev_glyph.char][glyph.char] * font.config.width;
								}}}
							} else return 0.0;
						}
						default: macro {
							return 0.0;
						}
					}}					
				}
				
				// -------------------------------------------------

				inline function setPosition(glyph:$glyphType, charData:$charDataType, x:Float, y:Float)
				{					
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							${switch (glyphStyleHasField.local_width) {
								case true: macro glyph.x = x + charData.metric.left * glyph.width;
								default: switch (glyphStyleHasField.width) {
									case true: macro glyph.x = x + charData.metric.left * fontStyle.width;
									default: macro glyph.x = x + charData.metric.left * font.config.width;
							}}}
							${switch (glyphStyleHasField.local_height) {
								case true: macro glyph.y = y + (charData.fontData.height + charData.fontData.descender - charData.metric.top) * glyph.height;
								default: switch (glyphStyleHasField.height) {
									case true: macro glyph.y = y + (charData.fontData.height + charData.fontData.descender - charData.metric.top) * fontStyle.height;
									default: macro glyph.y = y + (charData.fontData.height + charData.fontData.descender - charData.metric.top) * font.config.height;
							}}}							
						}
						default: macro // ------- simple font -------
						{
							glyph.x = x;
							glyph.y = y;
						}
					}}
				}
				
				inline function setSize(glyph:$glyphType, charData:$charDataType)
				{
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							${switch (glyphStyleHasField.local_width) {
								case true: macro glyph.w = charData.metric.width * glyph.width;
								default: switch (glyphStyleHasField.width) {
									case true: macro glyph.w = charData.metric.width * fontStyle.width;
									default: macro glyph.w = charData.metric.width * font.config.width;
							}}}
							${switch (glyphStyleHasField.local_height) {
								case true: macro glyph.h = charData.metric.height * glyph.height;
								default: switch (glyphStyleHasField.height) {
									case true: macro glyph.h = charData.metric.height * fontStyle.height;
									default: macro glyph.h = charData.metric.height * font.config.height;
							}}}
						}
						default: macro {} // ------- simple font have no metric
					}}
				}
				
				inline function setCharcode(glyph:$glyphType, charcode:Int, charData:$charDataType)
				{
					glyph.char = charcode;
					
					${switch (glyphStyleHasMeta.multiTexture) {
						case true: macro glyph.unit = charData.unit;
						default: macro {}
					}}
					${switch (glyphStyleHasMeta.multiSlot) {
						case true: macro glyph.slot = charData.slot;
						default: macro {}
					}}
					
					${switch (glyphStyleHasMeta.packed)
					{
						case true: macro // ------- Gl3Font -------
						{
							// TODO: let glyphes-width also include metrics with tex-offsets on need
							glyph.tx = charData.metric.u; // TODO: offsets for THICK letters
							glyph.ty = charData.metric.v;
							glyph.tw = charData.metric.w;
							glyph.th = charData.metric.h;							
						}
						default: macro // ------- simple font -------
						{
							glyph.tile = charcode - charData.min;
						}
					}}
				
				}
				
				// -----------------------------------------
				// ---------------- Glyphes ----------------
				// -----------------------------------------
				
				public inline function addGlyph(glyph:$glyphType, charcode:Int, x:Float, y:Float, glyphStyle:$styleType = null):Bool {
					var charData = getCharData(charcode);
					if (charData != null) {
						glyphSetStyle(glyph, glyphStyle);
						setCharcode(glyph, charcode, charData);
						setSize(glyph, charData);
						glyph.x = x;
						glyph.y = y;
						_buffer.addElement(glyph);
						return true;
					} else return false;
				}
								
				public inline function removeGlyph(glyph:$glyphType):Void {
					_buffer.removeElement(glyph);
				}
								
				public inline function updateGlyph(glyph:$glyphType):Void {
					_buffer.updateElement(glyph);
				}
				
				public inline function glyphSetStyle(glyph:$glyphType, glyphStyle:$styleType) {
					glyph.setStyle((glyphStyle != null) ? glyphStyle : fontStyle);
				}

				// sets position in depend of metrics-data
				// TODO: put at a baseline and special for simple font
				public inline function glyphSetPosition(glyph:$glyphType, x:Float, y:Float) {
					var charData = getCharData(glyph.char);
					setPosition(glyph, charData, x, y);
				}

				public inline function glyphSetChar(glyph:$glyphType, charcode:Int):Bool
				{
					var charData = getCharData(charcode);
					if (charData != null) {
						setCharcode(glyph, charcode, charData);
						setSize(glyph, charData);
						return true;
					} else return false;
				}
				
				// -----------------------------------------
				// ---------------- Lines ------------------
				// -----------------------------------------
				public function addLine(line:Line<$styleType>, chars:String, x:Float=0, y:Float=0, glyphStyle:$styleType = null):Bool
				{
					// TODO: add/remove withouth loosing the glyphes
					
					trace("addLine");
					var ret = true;
					line.x = x;
					line.y = y;
					var glyph:Glyph<$styleType>;
					var prev_glyph:Glyph<$styleType> = null;
					var charData:$charDataType;
					haxe.Utf8.iter(chars, function(charcode)
					{
						charData = getCharData(charcode);
						if (charData != null)
						{
							glyph = new Glyph<$styleType>();
							line.glyphes.push(glyph);
							glyphSetStyle(glyph, glyphStyle);
							setCharcode(glyph, charcode, charData);
							setSize(glyph, charData);
							${switch (glyphStyleHasMeta.packed) {
								case true: macro x += kerningOffset(prev_glyph, glyph, charData.fontData.kerning);
								default: macro {}
							}}
							trace(String.fromCharCode(charcode), x);
							setPosition(glyph, charData, x, y);
							x += nextGlyphOffset(glyph, charData);
							_buffer.addElement(glyph);
							prev_glyph = glyph;
						} 
						else ret = false;
					});
					
					${switch (glyphStyleHasMeta.packed) {
						case true: macro {
							if (prev_glyph != null) {
								var lm = getLineMetric(prev_glyph, charData.fontData);
								line.ascender = lm.asc;
								line.height = lm.desc;
								line.base = lm.base;
								trace("line metric:", line.height, line.base);
							}
						}
						default: macro {}
					}}
					return ret;
				}
				
				public function removeLine(line:Line<$styleType>)
				{
					for (glyph in line.glyphes) {
						removeGlyph(glyph);
					}
				}
				
				// ----------- change Line Style and Position ----------------
				
/*				public function lineSetStyle(line:Line<$styleType>, glyphStyle:$styleType, from:Int = 0, to:Null<Int> = null)
				{
					if (to == null) to = line.glyphes.length;
					
					if (from < line.updateFrom) line.updateFrom = from;
					if (to > line.updateTo) line.updateTo = to;
					
					if (from == 0) {
						penX = line.x;
						prev_charcode = -1;
					}
					else {
						penX = rightGlyphPos(line.glyphes[from - 1]);
						prev_charcode = line.glyphes[from - 1].char;
						// TODO: prev_scale
					}
						
					for (i in from...to) {
						line.glyphes[i].setStyle(glyphStyle);
						_lineSetCharcode(i, line, false, (i == to - 1 && i + 1 < line.glyphes.length));
					}
					
				}
				
				inline function _lineSetCharcode (i:Int, line:Line<$styleType>, isNewChar:Bool = true, isLast:Bool = true):Bool {
					// TODO: callback if line height is changing
					// this also not need for every char in loops !
					penY = line.y;
					var lm = getLineMetric(line.glyphes[i]);
					if (line.height != lm.desc) { // TODO: return metric from setCharcode() or integrate metric into glyph
						penY = line.y + (line.base - lm.base);
						//trace("line metric new style:", penY, line.height, line.base);
					}
					
					if (setCharcode(line.glyphes[i], line.glyphes[i].char, isNewChar))
					{
						if (isLast) // last
						{
							var offset = penX - leftGlyphPos(line.glyphes[i+1], (font.kerning) ? line.glyphes[i].char : -1);
							if (offset != 0.0) {
								//trace("REST:"+String.fromCharCode(line.chars[i + 1]), penX, line.glyphes[i + 1].x);
								_setLinePositionOffset(line, offset, 0, i + 1, line.glyphes.length);
								line.updateTo = line.glyphes.length;
							}
						}
						return true;
					} else return false;
				}
						
				public function lineSetPosition(line:Line<$styleType>, xNew:Float, yNew:Float)
				{
					_setLinePositionOffset(line, xNew - line.x, yNew - line.y, 0, line.glyphes.length); 
					line.x = xNew;
					line.y = yNew;
					line.updateFrom = 0;
					line.updateTo = line.glyphes.length;
				}
				
				inline function _setLinePositionOffset(line:Line<$styleType>, deltaX:Float, deltaY:Float, from:Int, to:Int)
				{
					if (deltaX == 0)
						for (i in from...to) line.glyphes[i].y += deltaY;
					else if (deltaY == 0)
						for (i in from...to) line.glyphes[i].x += deltaX;
					else 
						for (i in from...to) {
							line.glyphes[i].x += deltaX;
							line.glyphes[i].y += deltaY;
						}
				}
				
				// ------------ set/insert/delete chars from a line ---------------
				
				public function lineSetChar(line:Line<$styleType>, charcode:Int, position:Int=0, glyphStyle:$styleType = null):Bool
				{
					if (position < line.updateFrom) line.updateFrom = position;
					if (position + 1 > line.updateTo) line.updateTo = position + 1;
					
					if (position == 0) {
						penX = line.x;
						prev_charcode = -1;
					}
					else {
						penX = rightGlyphPos(line.glyphes[position - 1]);
						prev_charcode = line.glyphes[position - 1].char;
					}
					line.glyphes[position].char = charcode;
					if (glyphStyle != null) line.glyphes[position].setStyle(glyphStyle);
					return _lineSetCharcode(position, line);					
				}
				
				public function lineSetChars(line:Line<$styleType>, chars:String, position:Int=0, glyphStyle:$styleType = null):Bool
				{
					if (position < line.updateFrom) line.updateFrom = position;
					if (position + chars.length > line.updateTo) line.updateTo = Std.int(Math.min(position + chars.length, line.glyphes.length));
					
					if (position == 0) {
						penX = line.x;
						prev_charcode = -1;
					}
					else {
						penX = rightGlyphPos(line.glyphes[position - 1]);
						prev_charcode = line.glyphes[position - 1].char;
					}
					var i = position;
					var ret = true;
					haxe.Utf8.iter(chars, function(charcode)
					{
						if (i < line.glyphes.length) {
							line.glyphes[i].char = charcode;
							if (glyphStyle != null) line.glyphes[i].setStyle(glyphStyle);
							if (! _lineSetCharcode(i, line, true, (i == position + chars.length - 1 && i + 1 < line.glyphes.length))) ret = false;
						}
						else if (! lineInsertChar(line, charcode, i, glyphStyle)) ret = false; // TODO: optimize if much use of
						i++;
					});
					return ret;
				}
				
				public function lineInsertChar(line:Line<$styleType>, charcode:Int, position:Int = 0, glyphStyle:$styleType = null):Bool
				{
					var glyph = new Glyph<$styleType>();
					glyph.char = charcode;
					glyph.setStyle((glyphStyle != null) ? glyphStyle : fontStyle);

					line.glyphes.insert(position, glyph);
					
					penY = line.y;
					var lm = getLineMetric(glyph);
					if (line.height != lm.desc) { // TODO: separate function to get metric first
						penY = line.y + (line.base - lm.base);
					}
					
					if (position == 0) {
						penX = line.x;
						prev_charcode = -1;
					}
					else {
						penX = rightGlyphPos(line.glyphes[position - 1]);
						prev_charcode = line.glyphes[position - 1].char;
					}
					var startPenX = penX;
					
					if (setCharcode(glyph, charcode)) {
						_buffer.addElement(glyph);
						if (position + 1 < line.glyphes.length) {
							if (position + 1 < line.updateFrom) line.updateFrom = position + 1;
							line.updateTo = line.glyphes.length;
							_setLinePositionOffset(line, penX - startPenX, 0, position + 1, line.glyphes.length);
						}
						return true;
					} else return false;
				}
				
				public function lineInsertChars(line:Line<$styleType>, chars:String, position:Int = 0, glyphStyle:$styleType = null):Bool 
				{					
					var ret = true;
					var first = true;
					
					if (position == 0) {
						penX = line.x;
						prev_charcode = -1;
					}
					else {
						penX = rightGlyphPos(line.glyphes[position - 1]);
						prev_charcode = line.glyphes[position - 1].char;
					}
					var startPenX = penX;
					
					var rest = line.glyphes.splice(position, line.glyphes.length-position);
					haxe.Utf8.iter(chars, function(charcode)
					{
						var glyph = new Glyph<$styleType>();
						glyph.setStyle((glyphStyle != null) ? glyphStyle : fontStyle);
						line.glyphes.push(glyph);
						if (first) {
							first = false;
							var lm = getLineMetric(glyph);
							if (line.height != lm.desc) { // TODO: separate function to get metric first
								penY = line.y + (line.base - lm.base);
							} else penY = line.y;
						}
						if (setCharcode(glyph, charcode)) {
							_buffer.addElement(glyph);
						} else ret = false;
					
					});
					if (rest.length > 0 && ret) {
						if (line.glyphes.length < line.updateFrom) line.updateFrom = line.glyphes.length;
						line.glyphes = line.glyphes.concat(rest);
						line.updateTo = line.glyphes.length;
						_setLinePositionOffset(line, penX - startPenX, 0, line.glyphes.length - rest.length, line.glyphes.length);
					}
					return ret;
				}
				
				public function lineDeleteChar(line:Line<$styleType>, position:Int = 0)
				{
					removeGlyph(line.glyphes.splice(position, 1)[0]);
					_lineDeleteCharsOffset(line, position, position + 1);
				}
				
				public function lineDeleteChars(line:Line<$styleType>, from:Int = 0, to:Null<Int> = null)
				{
					if (to == null) to = line.glyphes.length;
					for (glyph in line.glyphes.splice(from, to - from)) removeGlyph(glyph);
					_lineDeleteCharsOffset(line, from, to);
				}
				
				inline function _lineDeleteCharsOffset(line:Line<$styleType>, from:Int, to:Int)
				{
					if (from < line.glyphes.length) {
						var offset:Float = 0.0;
						if (from == 0) offset = line.x - leftGlyphPos(line.glyphes[from], -1);
						else offset = rightGlyphPos(line.glyphes[from-1]) - leftGlyphPos(line.glyphes[from], line.glyphes[from-1].char);
						if (from < line.updateFrom) line.updateFrom = from;
						line.updateTo = line.glyphes.length;
						_setLinePositionOffset(line, offset, 0, from, line.glyphes.length);
					}
					else {trace(line.updateFrom, line.updateTo);
						if (line.updateTo > from && line.updateFrom < from) line.updateTo = from;
						else {
							line.updateFrom = 0x1000000;
							line.updateTo = 0;
						}
					}
				}
				
				// ------------- update line ---------------------
				
				public function updateLine(line:Line<$styleType>, from:Null<Int> = null, to:Null<Int> = null)
				{
					if (from != null) line.updateFrom = from;
					if (to != null) line.updateTo = to;
					
					trace("update from "+ line.updateFrom + " to " +line.updateTo);
					for (i in line.updateFrom...line.updateTo) 
						updateGlyph(line.glyphes[i]);

					line.updateFrom = 0x1000000;
					line.updateTo = 0;
				}
*/			
			} // end class

			// -------------------------------------------------------------------------------------------
			// -------------------------------------------------------------------------------------------
			
			Context.defineModule(classPackage.concat([className]).join('.'),[c]);
		}
		return TPath({ pack:classPackage, name:className, params:[] });
	}
}
#end
