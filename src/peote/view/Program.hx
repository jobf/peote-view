package peote.view;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import peote.view.PeoteGL.GLProgram;
import peote.view.PeoteGL.GLShader;
import peote.view.PeoteGL.GLUniformLocation;

import peote.view.utils.Util;
import peote.view.utils.GLTool;
import peote.view.utils.RenderList;
import peote.view.utils.RenderListItem;

class ActiveTexture {
	public var unit:Int;
	public var texture:Texture;
	public var uniformLoc:GLUniformLocation;
	public function new(unit:Int, texture:Texture, uniformLoc:GLUniformLocation) {
		this.unit = unit;
		this.texture = texture;
		this.uniformLoc = uniformLoc;
	}
}

@:allow(peote.view)
class Program 
{
	public var alphaEnabled:Bool;
	public var zIndexEnabled:Bool;
	public var autoUpdateTextures:Bool = true;
	
	var display:Display = null;
	var gl:PeoteGL = null;

	var glProgram:GLProgram = null;
	var glProgramPicking:GLProgram = null;
	var glVertexShader:GLShader = null;
	var glFragmentShader:GLShader = null;
	var glVertexShaderPicking:GLShader = null;
	var glFragmentShaderPicking:GLShader = null;
	
	var buffer:BufferInterface; // TODO: make public with getter/setter
	
	var glShaderConfig = {
		isPICKING: false,
		isES3: false,
		isINSTANCED: false,
		isUBO: false,
		IN: "attribute",
		VARIN: "varying",
		VAROUT: "varying",
		hasTEXTURES: false,
		FRAGMENT_PROGRAM_UNIFORMS:"",
		FRAGMENT_CALC_LAYER:"",
		TEXTURES:[],
		isDISCARD: true,
		DISCARD: "0.0",
	};
	
	var textureList = new RenderList<ActiveTexture>(new Map<ActiveTexture,RenderListItem<ActiveTexture>>());
	var textureLayers = new IntMap<Array<Texture>>();
	var activeTextures = new Array<Texture>();
	var activeUnits = new Array<Int>();

	var colorIdentifiers:Array<String>;

	var textureIdentifiers:Array<String>;
	var customTextureIdentifiers = new Array<String>();
	
	var defaultFormulaVars:StringMap<Color>;
	var defaultColorFormula:String;
	var colorFormula = "";
	

	public function new(buffer:BufferInterface) 
	{
		this.buffer = buffer;
		alphaEnabled = buffer.hasAlpha();
		zIndexEnabled = buffer.hasZindex();
		
		colorIdentifiers = buffer.getColorIdentifiers();
		textureIdentifiers = buffer.getTextureIdentifiers();
		
		defaultColorFormula = buffer.getDefaultColorFormula();
		trace("defaultColorFormula = ", defaultColorFormula);
		defaultFormulaVars = buffer.getDefaultFormulaVars();
		trace("defaultFormulaVars = ", defaultFormulaVars);
		
		parseColorFormula();
	}
	
 	private inline function isIn(display:Display):Bool
	{
		return (this.display == display);
	}
			
	private inline function addToDisplay(display:Display):Bool
	{
		trace("Program added to Display");
		if (this.display == display) return false; // is already added
		else
		{	
			// if added to another one remove it frome there first
			if (this.display != null) this.display.removeProgram(this);  // <-- TODO: allow multiple displays !!!
			
			this.display = display;
			
			if (gl != display.gl) // new or different GL-Context
			{	
				if (gl != null) clearOldGLContext(); // different GL-Context
				setNewGLContext(display.gl); //TODO: check that this is not Null
			}
			else if (PeoteGL.Version.isUBO)
			{	// if Display is changed but same gl-context -> bind to UBO of new Display
				if (gl!=null) display.uniformBuffer.bindToProgram(gl, glProgram, "uboDisplay", 1);
			}
			
			return true;
		}	
	}

	private inline function removedFromDisplay():Void
	{
		display = null;
	}
		
	
	private inline function setNewGLContext(newGl:PeoteGL)
	{
		trace("Program setNewGLContext");
		gl = newGl;
		buffer._gl = gl;          // TODO: check here if buffer already inside another peoteView with different glContext (multiwindows)
		buffer.createGLBuffer();
		buffer.updateGLBuffer();
		
		for (t in activeTextures) t.setNewGLContext(newGl);
		
		if (PeoteGL.Version.isES3) {
			glShaderConfig.isES3 = true;
			glShaderConfig.IN = "in";
			glShaderConfig.VARIN = "in";
			glShaderConfig.VAROUT = "out";
		}
		if (PeoteGL.Version.isUBO)       glShaderConfig.isUBO = true;
		if (PeoteGL.Version.isINSTANCED) glShaderConfig.isINSTANCED = true;
		
		createProgram();
	}

	private inline function clearOldGLContext() 
	{
		trace("Program clearOldGLContext");
		deleteProgram();
		buffer.deleteGLBuffer();
		for (t in activeTextures) t.clearOldGLContext();
	}

	private inline function reCreateProgram():Void 
	{
		deleteProgram();
		createProgram();
	}
	
	private inline function deleteProgram()
	{
		gl.deleteShader(glVertexShader);
		gl.deleteShader(glFragmentShader);
		gl.deleteProgram(glProgram);
		if (buffer.hasPicking()) {
			gl.deleteShader(glVertexShaderPicking);
			gl.deleteShader(glFragmentShaderPicking);
			gl.deleteProgram(glProgramPicking);	
		}
	}
	
	private inline function createProgram() {
		createProg();
		if (buffer.hasPicking()) createProg(true);		
	}
	
	private function createProg(isPicking:Bool = false):Void  // TODO: do not compile twice if same program is used inside multiple displays
	{
		trace("create GL-Program" + ((isPicking) ? " for opengl-picking" : ""));
		glShaderConfig.isPICKING = (isPicking) ? true : false;
		
		var glVShader = GLTool.compileGLShader(gl, gl.VERTEX_SHADER,   GLTool.parseShader(buffer.getVertexShader(),   glShaderConfig), true );
		var glFShader = GLTool.compileGLShader(gl, gl.FRAGMENT_SHADER, GLTool.parseShader(buffer.getFragmentShader(), glShaderConfig), true );

		var glProg = gl.createProgram();

		gl.attachShader(glProg, glVShader);
		gl.attachShader(glProg, glFShader);
		
		buffer.bindAttribLocations(gl, glProg);
				
		textureList.clear(); // maybe optimize later with own single-linked list here!

		GLTool.linkGLProgram(gl, glProg);
		
		// create textureList with new unitormlocations
		for (i in 0...activeTextures.length) {
			textureList.add(new ActiveTexture(activeUnits[i], activeTextures[i], gl.getUniformLocation(glProg, "uTexture" + i)), null, false );
		}
		
		if ( !isPicking && PeoteGL.Version.isUBO)
		{
			display.peoteView.uniformBuffer.bindToProgram(gl, glProg, "uboView", 0);
			display.uniformBuffer.bindToProgram(gl, glProg, "uboDisplay", 1); // TODO: multiple displays
		}
		else
		{	// Try to optimize here to let use picking shader the same vars
			if ( !isPicking ) {
				uRESOLUTION = gl.getUniformLocation(glProg, "uResolution");
				uZOOM = gl.getUniformLocation(glProg, "uZoom");
				uOFFSET = gl.getUniformLocation(glProg, "uOffset");
			} else {
				uRESOLUTION_PICK = gl.getUniformLocation(glProg, "uResolution");
				uZOOM_PICK = gl.getUniformLocation(glProg, "uZoom");
				uOFFSET_PICK = gl.getUniformLocation(glProg, "uOffset");
			}
		}
		if ( !isPicking )
			uTIME = gl.getUniformLocation(glProg, "uTime");
		else uTIME_PICK = gl.getUniformLocation(glProg, "uTime");
		
		if (!isPicking) {
			glProgram = glProg;
			glVertexShader = glVShader;
			glFragmentShader  = glFShader;
		} else {
			glProgramPicking = glProg;
			glVertexShaderPicking = glVShader;
			glFragmentShaderPicking  = glFShader;
		}
		
	}
	
	var uRESOLUTION:GLUniformLocation;
	var uZOOM:GLUniformLocation;
	var uOFFSET:GLUniformLocation;
	var uTIME:GLUniformLocation;
	// TODO: optimize here (or all with typedef {uRESOLUTION:GLUniformLocation ...} )
	var uRESOLUTION_PICK:GLUniformLocation;
	var uZOOM_PICK:GLUniformLocation;
	var uOFFSET_PICK:GLUniformLocation;
	var uTIME_PICK:GLUniformLocation;
	
	private function parseColorFormula():Void {
		var formula:String = "";
		
		if (colorFormula != "") formula = colorFormula;
		else if (defaultColorFormula != "") formula = defaultColorFormula;
		else {
			var col = colorIdentifiers.copy();
			var tex = new Array<String>();
			for (i in 0...textureIdentifiers.length) 
				if (textureLayers.exists(i)) tex.push(textureIdentifiers[i]);
			for (i in 0...customTextureIdentifiers.length)
				if (textureLayers.exists(textureIdentifiers.length+i)) tex.push(customTextureIdentifiers[i]);
			
			// mix(mix(...))*restColor
			if (col.length + tex.length == 0) formula = Color.RED.toGLSL();
			else {
				if (tex.length > 0) {
					formula = tex.shift();
					if (col.length > 0) formula = '${col.shift()} * $formula';
				}
				for (t in tex) {
					if (col.length > 0) t = '${col.shift()} * $t ';
					formula = 'mix( $formula, $t, ($t).a )';
				}
				// if more colors than textures add/multiply the Rest
				while (col.length > 0) {
					formula += ((formula != "") ? "*": "") + col.shift();
					if (col.length > 0) formula = '($formula + ${col.shift()})';					
				}				
			}
			
		}
		for (i in 0...colorIdentifiers.length) {
			var regexp = new EReg('(.*?\\b)${colorIdentifiers[i]}(\\b.*?)', "g");
			if (regexp.match(formula))
				if (regexp.matched(1).substr(-1,1) != ".")
					formula = regexp.replace( formula, '$1' + "c" + i +'$2' );
		}
		for (i in 0...textureIdentifiers.length) {
			var regexp = new EReg('(.*?\\b)${textureIdentifiers[i]}(\\b.*?)', "g");
			if (regexp.match(formula))
				if (textureLayers.exists(i) && regexp.matched(1).substr(-1,1) != ".")
					formula = regexp.replace( formula, '$1' + "t" + i +'$2' );
		}
		for (i in 0...customTextureIdentifiers.length) {
			var regexp = new EReg('(.*?\\b)${customTextureIdentifiers[i]}(\\b.*?)', "g");
			if (regexp.match(formula))
				if (textureLayers.exists(textureIdentifiers.length+i) && regexp.matched(1).substr(-1,1) != ".")
					formula = regexp.replace( formula, '$1' + "t"+(textureIdentifiers.length+i) +'$2' );
		}
		// fill the REST with default values:
		for (name in defaultFormulaVars.keys()) {
			//var regexp = new EReg('(.*?\\b)${name}(.[rgbaxyz]+)?(\\b.*?)', "g");
			var regexp = new EReg('(.*?\\b)${name}(\\b.*?)', "g");
			if (regexp.match(formula))
				if (regexp.matched(1).substr(-1,1) != ".")
						formula = regexp.replace( formula, '$1' + defaultFormulaVars.get(name).toGLSL() + '$2' );
			//formula = regexp.replace( formula, '$1' + defaultFormulaVars.get(name).toGLSL('$2') + '$3' );
		}
		
		glShaderConfig.FRAGMENT_CALC_LAYER = formula;
	}
	
	public function setColorFormula(formula:String, varDefaults:StringMap<Color>=null, ?autoUpdateTextures:Null<Bool>):Void {
		colorFormula = formula;
		if (varDefaults != null)
			for (name in varDefaults.keys()) {
				if (Util.isWrongIdentifier(name)) throw('Error: "$name" is not an identifier, please use only letters/numbers or "_" (starting with a letter)');
				defaultFormulaVars.set(name, varDefaults.get(name));
			}
		if (autoUpdateTextures != null) { if (autoUpdateTextures) updateTextures(); }
		else if (this.autoUpdateTextures) updateTextures();
	}
	
	function getTextureIndexByIdentifier(identifier:String, addNew:Bool = true):Int {
		var layer = textureIdentifiers.indexOf(identifier);
		if (layer < 0) {
			layer = customTextureIdentifiers.indexOf(identifier);
			if (layer < 0) {
				if (addNew) {
					if (Util.isWrongIdentifier(identifier)) throw('Error: "$identifier" is not an identifier, please use only letters/numbers or "_" (starting with a letter)');
					trace('adding custom texture layer "$identifier"');
					layer = textureIdentifiers.length + customTextureIdentifiers.length;
					customTextureIdentifiers.push(identifier); // adds a custom identifier
				}
			}	
		}
		return layer;
	}
	
	// discard pixels with alpha lower then 
	public function discardAtAlpha(?atAlphaValue:Null<Float>, ?autoUpdateTextures:Null<Bool>) {
		if (atAlphaValue == null) {
			glShaderConfig.isDISCARD = false;
		}
		else {
			glShaderConfig.isDISCARD = true;
			glShaderConfig.DISCARD = Util.toFloatString(atAlphaValue);
		}
		checkAutoUpdate(autoUpdateTextures);
	}
	
	// set a texture-layer
	public function setTexture(texture:Texture, identifier:String, ?autoUpdateTextures:Null<Bool>):Void {
		trace("(re)set texture of a layer");
		var layer = getTextureIndexByIdentifier(identifier);
		textureLayers.set(layer, [texture]);
		checkAutoUpdate(autoUpdateTextures);
	}
	
	// multiple textures per layer (to switch between them via unit-attribute)
	public function setMultiTexture(textureUnits:Array<Texture>, identifier:String, ?autoUpdateTextures:Null<Bool>):Void {
		trace("(re)set texture-units of a layer");
		var layer = getTextureIndexByIdentifier(identifier);
		if (textureUnits == null) throw("Error, textureUnits need to be an array of textures");
		if (textureUnits.length == 0) throw("Error, textureUnits needs at least 1 texture");
		var i = textureUnits.length;
		while (i-- > 0)
			if (textureUnits[i] == null) throw("Error, texture is null.");
			else if (textureUnits.indexOf(textureUnits[i]) != i) throw("Error, textureLayer can not contain same texture twice.");		
		textureLayers.set(layer, textureUnits);
		checkAutoUpdate(autoUpdateTextures);
	}
	
	// add a texture to textuer-units
	public function addTexture(texture:Texture, identifier:String, ?autoUpdateTextures:Null<Bool>):Void {
		trace("add texture into units of " + identifier);
		var layer = getTextureIndexByIdentifier(identifier);
		if (texture == null) throw("Error, texture is null.");
		var textures:Array<Texture> = textureLayers.get(layer);
		if (textures != null) {
			if (textures.indexOf(texture) >= 0) throw("Error, textureLayer already contains this texture.");
			else {
				textures.push(texture);
				textureLayers.set(layer, textures);
			}
		}
		else textureLayers.set(layer, [texture]);
		checkAutoUpdate(autoUpdateTextures);
	}
	
	public function removeTexture(texture:Texture, identifier:String, ?autoUpdateTextures:Null<Bool>):Void {
		trace("remove texture from textureUnits of a layer");
		var layer = getTextureIndexByIdentifier(identifier, false);
		if (layer < 0) throw('Error, textureLayer "$identifier" did not exists.');
		if (texture == null) throw("Error, texture is null.");
		textureLayers.get(layer).remove(texture);
		if (textureLayers.get(layer).length == 0) {
			textureLayers.remove(layer);
			customTextureIdentifiers.remove(identifier);
		}
		checkAutoUpdate(autoUpdateTextures);
	}
	
	public function removeAllTexture(identifier:String, ?autoUpdateTextures:Null<Bool>):Void {
		trace("remove all textures from a layer");
		var layer = getTextureIndexByIdentifier(identifier, false);
		if (layer < 0) throw('Error, textureLayer "$identifier" did not exists.');
		textureLayers.remove(layer);
		customTextureIdentifiers.remove(identifier);
		checkAutoUpdate(autoUpdateTextures);
	}
	
	inline function checkAutoUpdate(autoUpdateTextures:Null<Bool>) {
		if (autoUpdateTextures != null) { if (autoUpdateTextures) updateTextures(); }
		else if (this.autoUpdateTextures) updateTextures();
	}
	
	// TODO: replaceTexture(textureToReplace:Texture, newTexture:Texture)
	
 	public function hasTexture(texture:Texture, identifier:Null<String>=null):Bool
	{
		if (texture == null) throw("Error, texture is null.");
		if (identifier == null) {
			for (t in activeTextures) if (t == texture) return true;
		}
		else {
			var textures = textureLayers.get(getTextureIndexByIdentifier(identifier, false));
			if (textures != null)
				if (textures.indexOf(texture) >= 0 ) return true;
		}
		return false;
	}
	
	// ------------------------------------
	
	public function updateTextures():Void {
		trace("update Textures");
		// collect new or removed old textures
		var newTextures = new Array<Texture>();
		for (layer in textureLayers.keys()) {
			for (t in textureLayers.get(layer)) {
				if (newTextures.indexOf(t) < 0) newTextures.push(t);
			}
		}
		
		var i = activeTextures.length;
		while (i-- > 0) 
			if (newTextures.indexOf(activeTextures[i]) < 0) { // remove texture
				trace("REMOVE texture",i);
				activeTextures[i].removedFromProgram();
				activeTextures.splice(i, 1);
				activeUnits.splice(i, 1);
			}
		
		for (t in newTextures) {
			if (activeTextures.indexOf(t) < 0) { // add texture
				trace("ADD texture", activeTextures.length);
				activeTextures.push(t);
				var unit = 0;
				while (activeUnits.indexOf(unit) >= 0 ) unit++;
				activeUnits.push(unit);
				if (! t.setToProgram(this)) throw("Error, texture already used by another program into different gl-context");
			}
		}
				
		// -----------
		trace("textureLayers", [for (layer in textureLayers.keys()) layer]);
		
		parseColorFormula();
		
		if (activeTextures.length == 0) {
			glShaderConfig.hasTEXTURES = false;
		}
		else {
			glShaderConfig.hasTEXTURES = true;
			
			glShaderConfig.FRAGMENT_PROGRAM_UNIFORMS = "";
			for (i in 0...activeTextures.length)
				glShaderConfig.FRAGMENT_PROGRAM_UNIFORMS += 'uniform sampler2D uTexture$i;';
			
			// fill texture-layer in template
			glShaderConfig.TEXTURES = [];
			for (layer in textureLayers.keys()) {
				var units = new Array < {UNIT_VALUE:String, TEXTURE:String,
										SLOTS_X:String, SLOTS_Y:String, SLOT_WIDTH:String, SLOT_HEIGHT:String,
										SLOTS_WIDTH:String, SLOTS_HEIGHT:String,
										TILES_X:String, TILES_Y:String,
										TEXTURE_WIDTH:String, TEXTURE_HEIGHT:String,
										FIRST:Bool, LAST:Bool}>();
				var textures = textureLayers.get(layer);
				for (i in 0...textures.length) {
					units.push({
						UNIT_VALUE:(i + 1) + ".0",
						TEXTURE:"uTexture" + activeTextures.indexOf(textures[i]),
						SLOTS_X: textures[i].slotsX + ".0",
						SLOTS_Y: textures[i].slotsY + ".0",
						SLOT_WIDTH:  textures[i].slotWidth  + ".0",
						SLOT_HEIGHT: textures[i].slotHeight + ".0",
						SLOTS_WIDTH:  Std.int(textures[i].slotsX * textures[i].slotWidth ) + ".0",
						SLOTS_HEIGHT: Std.int(textures[i].slotsY * textures[i].slotHeight) + ".0",
						TILES_X: textures[i].tilesX + ".0",
						TILES_Y: textures[i].tilesY + ".0",
						TEXTURE_WIDTH: textures[i].width + ".0",
						TEXTURE_HEIGHT:textures[i].height + ".0",
						FIRST:((i == 0) ? true : false), LAST:((i == textures.length - 1) ? true : false)
					});
				}
				trace("LAYER:", layer, units);
				glShaderConfig.TEXTURES.push({LAYER:layer, UNITS:units});
			}
		}
		
		if (gl != null) reCreateProgram(); // recompile shaders			
	}
	
	
	public function setActiveTextureGlIndex(texture:Texture, index:Int):Void {
		trace("set texture index to " + index);
		var oldUnit:Int = -1;
		var j:Int = -1;
		for (i in 0...activeTextures.length) {
			if (activeTextures[i] == texture) {
				oldUnit = activeUnits[i];
				activeUnits[i] = index;
			}
			else if (index == activeUnits[i]) j = i;
		}
		if (oldUnit == -1) throw("Error, texture is not in use, try setTextureLayer(layer, [texture]) before setting unit-number manual");
		if (j != -1) activeUnits[j] = oldUnit;
		
		// update textureList units
		j = 0;
		for (t in textureList) t.unit = activeUnits[j++];
	}
	
	// ------------------------------------------------------------------------------
	// ----------------------------- Render -----------------------------------------
	// ------------------------------------------------------------------------------
	var textureListItem:RenderListItem<ActiveTexture>;

	private inline function render_activeTextureUnits(peoteView:PeoteView):Void {
		// Texture Units
		textureListItem = textureList.first;
		while (textureListItem != null)
		{
			if (textureListItem.value.texture.glTexture == null) trace("=======PROBLEM========");
			
			if ( peoteView.isTextureStateChange(textureListItem.value.unit, textureListItem.value.texture) ) {
				gl.activeTexture (gl.TEXTURE0 + textureListItem.value.unit);
				trace("activate Texture", textureListItem.value.unit);
				gl.bindTexture (gl.TEXTURE_2D, textureListItem.value.texture.glTexture);
				//gl.bindSampler(textureListItem.value.unit, sampler); // only ES3.0
				//gl.enable(gl.TEXTURE_2D); // is default ?
			}
			gl.uniform1i (textureListItem.value.uniformLoc, textureListItem.value.unit); // optimizing: later in this.uniformBuffer for isUBO
			textureListItem = textureListItem.next;
		}		
	}
	
	private inline function render(peoteView:PeoteView, display:Display)
	{	
		//trace("    ---program.render---");
		gl.useProgram(glProgram); // ------ Shader Program
		
		render_activeTextureUnits(peoteView);
		
		// TODO: custom uniforms per Program
		
		if (PeoteGL.Version.isUBO)
		{	
			// ------------- uniform block -------------
			//gl.bindBufferRange(gl.UNIFORM_BUFFER, 0, uProgramBuffer, 0, 8);
			gl.bindBufferBase(gl.UNIFORM_BUFFER, peoteView.uniformBuffer.block , peoteView.uniformBuffer.uniformBuffer);
			gl.bindBufferBase(gl.UNIFORM_BUFFER, display.uniformBuffer.block , display.uniformBuffer.uniformBuffer);
		}
		else
		{
			// ------------- simple uniform -------------
			gl.uniform2f (uRESOLUTION, peoteView.width, peoteView.height);
			gl.uniform1f (uZOOM, peoteView.zoom * display.zoom);
			gl.uniform2f (uOFFSET, (display.x + display.xOffset + peoteView.xOffset) / display.zoom, 
			                       (display.y + display.yOffset + peoteView.yOffset) / display.zoom);
			/*gl.uniform2f (uZOOM, peoteView.xZoom * display.xZoom, peoteView.yZoom * display.yZoom);
			gl.uniform2f (uOFFSET, (display.x + display.xOffset + peoteView.xOffset) / display.xZoom, 
			                       (display.y + display.yOffset + peoteView.yOffset) / display.yZoom);*/
		}
		
		gl.uniform1f (uTIME, peoteView.time);
		
		peoteView.setGLDepth(zIndexEnabled);
		peoteView.setGLAlpha(alphaEnabled);
		
		buffer.render(peoteView, display, this);
		gl.useProgram (null);
	}
	
	// ------------------------------------------------------------------------------
	// ------------------------ OPENGL PICKING -------------------------------------- 
	// ------------------------------------------------------------------------------
	private inline function pick( xOff:Float, yOff:Float, peoteView:PeoteView, display:Display):Void
	{
		gl.useProgram(glProgramPicking); // ------ Shader Program
		
		render_activeTextureUnits(peoteView);
		
		// No view/display UBOs for PICKING-SHADER!
		gl.uniform2f (uRESOLUTION_PICK, 1, 1);
		gl.uniform1f (uZOOM_PICK, peoteView.zoom * display.zoom);
		gl.uniform2f (uOFFSET_PICK, (display.x + display.xOffset + xOff) / display.zoom,
		                       (display.y + display.yOffset + yOff) / display.zoom);
		
		gl.uniform1f (uTIME_PICK, peoteView.time);
		
		peoteView.setGLDepth(zIndexEnabled);
		peoteView.setGLAlpha(false);
		
		buffer.render(peoteView, display, this);
		gl.useProgram (null);		
	}
	
}