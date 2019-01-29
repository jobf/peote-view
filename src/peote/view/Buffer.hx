package peote.view;

#if !macro
@:genericBuild(peote.view.Buffer.BufferMacro.build())
class Buffer<T> {}
#else

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.TypeTools;

class BufferMacro
{
	public static var cache = new Map<String, Bool>();
	
	static public function build()
	{	
		switch (Context.getLocalType()) {
			case TInst(_, [t]):
				switch (t) {
					case TInst(n, []):
						var g = n.get();
						var superName:String = null;
						var superModule:String = null;
						var s = g;
						while (s.superClass != null) {
							s = s.superClass.t.get(); //trace("->" + s.name);
							superName = s.name;
							superModule = s.module;
						}
						var missInterface = true;
						if (s.interfaces != null) for (i in s.interfaces) if (i.t.get().module == "peote.view.Element") missInterface = false;
						if (missInterface) throw Context.error('Error: Type parameter for buffer need to be generated by implementing "peote.view.Element"', Context.currentPos());
						
						return buildClass("Buffer",  g.pack, g.module, g.name, superModule, superName, TypeTools.toComplexType(t) );
					case t: Context.error("Class expected", Context.currentPos());
				}
			case t: Context.error("Class expected", Context.currentPos());
		}
		return null;
	}
	
	static public function buildClass(className:String, elementPack:Array<String>, elementModule:String, elementName:String, superModule:String, superName:String, elementType:ComplexType):ComplexType
	{		
		className += "_" + elementName;
		var classPackage = Context.getLocalClass().get().pack;
		
		if (!cache.exists(className))
		{
			cache[className] = true;
			
			var elemField:Array<String>;
			if (superName == null) elemField = elementModule.split(".").concat([elementName]);
			else elemField = superModule.split(".").concat([superName]);
			
			#if peoteview_debug_macro
			trace('generating Class: '+classPackage.concat([className]).join('.'));	
			/*
			trace("ClassName:"+className);           // Buffer_ElementSimple
			trace("classPackage:" + classPackage);   // [peote,view]	
			
			trace("ElementPackage:" + elementPack);  // [elements]
			trace("ElementModule:" + elementModule); // elements.ElementSimple
			trace("ElementName:" + elementName);     // ElementSimple
			
			trace("ElementType:" + elementType);     // TPath({ name => ElementSimple, pack => [elements], params => [] })
			trace("ElemField:" + elemField);
			*/
			#end
			
			var c = macro		
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------

class $className implements BufferInterface
{
	var _gl: peote.view.PeoteGL = null;
	var _glBuffer: peote.view.PeoteGL.GLBuffer;
	var _glInstanceBuffer: peote.view.PeoteGL.GLBuffer = null;
	var _glVAO: peote.view.PeoteGL.GLVertexArrayObject = null;

	var _elements: haxe.ds.Vector<$elementType>; // var elements:Int; TAKE CARE if same name as package! -> TODO!!
	var _maxElements:Int = 0; // amount of added elements (pos of last element)
	var _elemBuffSize:Int;
	
	// local bytes-buffer
	var _bytes: utils.Bytes;
	
	#if peoteview_queueGLbuffering
	var updateGLBufferElementQueue:Array<$elementType>;
	var setNewGLContextQueue:Array<PeoteGL>;
	/*var queueCreateGLBuffer:Bool = false;
	var queueDeleteGLBuffer:Bool = false;
	var queueUpdateGLBuffer:Bool = false;*/
	#end

	public function new(size:Int)
	{
		#if peoteview_queueGLbuffering
		updateGLBufferElementQueue = new Array<$elementType>();
		setNewGLContextQueue = new Array<PeoteGL>();
		#end
		
		_elements = new haxe.ds.Vector<$elementType>(size);
		
		if (peote.view.PeoteGL.Version.isINSTANCED) // TODO can be missing if buffer created before peoteView
		{
			$p{elemField}.createInstanceBytes();
		    _elemBuffSize = $p{elemField}.BUFF_SIZE_INSTANCED;
		}
		else _elemBuffSize = $p{elemField}.BUFF_SIZE * $p{elemField}.VERTEX_COUNT;
		
		trace("create bytes for GLbuffer");
		_bytes = utils.Bytes.alloc(_elemBuffSize * size);
		_bytes.fill(0, _elemBuffSize * size, 0);		
	}
	
	inline function setNewGLContext(newGl:PeoteGL)
	{
		#if peoteview_queueGLbuffering
		setNewGLContextQueue.push(newGl);
		#else
		_setNewGLContext(newGl);
		#end
	}
	inline function _setNewGLContext(newGl:PeoteGL)
	{
		if (newGl != null && newGl != _gl) // only if different GL - Context	
		{
			if (_gl != null) deleteGLBuffer(); // < ------- TODO BUGGY with different-context (see multiwindow sample)
			
			trace("Buffer setNewGLContext");	
			_gl = newGl;
			createGLBuffer();
			//updateGLBuffer();
		}
	}
	/*
	inline function createGLBuffer():Void
	{
		#if peoteview_queueGLbuffering
		queueCreateGLBuffer = true;
		#else
		_createGLBuffer();
		#end
	}*/
	inline function createGLBuffer():Void
	{
		trace("create new GlBuffer");
		_glBuffer = _gl.createBuffer();
		
		_gl.bindBuffer (_gl.ARRAY_BUFFER, _glBuffer);
		_gl.bufferData (_gl.ARRAY_BUFFER, _bytes.length, _bytes, _gl.STREAM_DRAW); // STATIC_DRAW, DYNAMIC_DRAW, STREAM_DRAW 
		_gl.bindBuffer (_gl.ARRAY_BUFFER, null);
		
		if (peote.view.PeoteGL.Version.isINSTANCED) { // init and update instance buffer
			_glInstanceBuffer = _gl.createBuffer();
			$p{elemField}.updateInstanceGLBuffer(_gl, _glInstanceBuffer);
		}
		if (peote.view.PeoteGL.Version.isVAO) { // init VAO 		
			_glVAO = _gl.createVertexArray();
			_gl.bindVertexArray(_glVAO);
			if (peote.view.PeoteGL.Version.isINSTANCED)
				$p{elemField}.enableVertexAttribInstanced(_gl, _glBuffer, _glInstanceBuffer);
			else $p{elemField}.enableVertexAttrib(_gl, _glBuffer);
			_gl.bindVertexArray(null);
		}
	}
	/*
	inline function deleteGLBuffer():Void
	{
		#if peoteview_queueGLbuffering
		queueDeleteGLBuffer = true;
		#else
		_deleteGLBuffer();
		#end
	}
	*/
	inline function deleteGLBuffer():Void
	{
		trace("delete GlBuffer");
		_gl.deleteBuffer(_glBuffer);
		
		if (peote.view.PeoteGL.Version.isINSTANCED)	_gl.deleteBuffer(_glInstanceBuffer);
		if (peote.view.PeoteGL.Version.isVAO) _gl.deleteVertexArray(_glVAO);
	}
	/*
	inline function updateGLBuffer():Void
	{
		#if peoteview_queueGLbuffering
		queueUpdateGLBuffer = true;
		#else
		//var t = haxe.Timer.stamp();
		_updateGLBuffer();
		//trace("updateGLBuffer time:"+(haxe.Timer.stamp()-t));
		#end
	}
	*/
	inline function updateGLBuffer():Void
	{
		_gl.bindBuffer (_gl.ARRAY_BUFFER, _glBuffer);
		//_gl.bufferData (_gl.ARRAY_BUFFER, _bytes.length, _bytes, _gl.STATIC_DRAW); // _gl.DYNAMIC_DRAW _gl.STREAM_DRAW
		//_gl.bufferData (_gl.ARRAY_BUFFER, _bytes.length, _bytes, _gl.STREAM_DRAW); // more performance if allways updating (on IE better then DYNAMIC_DRAW)
		_gl.bufferSubData(_gl.ARRAY_BUFFER, 0, _elemBuffSize*_maxElements, _bytes );
		//_gl.bufferSubData(_gl.ARRAY_BUFFER, 0, _elemBuffSize*_maxElements, new peote.view.PeoteGL.BytePointer(_bytes) );
		
		_gl.bindBuffer (_gl.ARRAY_BUFFER, null);
	}
	
	/**
        Updates all element-changes to the rendering process of this buffer.
    **/
	public function update():Void
	{
		//var t = haxe.Timer.stamp();
		for (i in 0..._maxElements) {
			if (peote.view.PeoteGL.Version.isINSTANCED)
				_elements.get(i).writeBytesInstanced(_bytes);
			else
				_elements.get(i).writeBytes(_bytes);
		}
		//trace("updateElement Bytes time:"+(haxe.Timer.stamp()-t));
		updateGLBuffer();
	}
	
	/**
        Updates all changes of an element to the rendering process.
        @param  element Element instance to update
    **/
	public function updateElement(element: $elementType):Void
	{
		if (peote.view.PeoteGL.Version.isINSTANCED)
			element.writeBytesInstanced(_bytes);
		else 
			element.writeBytes(_bytes);
			
		#if peoteview_queueGLbuffering
		updateGLBufferElementQueue.push(element);
		#else
		_updateElement(element);
		#end
	}
	
	public inline function _updateElement(element: $elementType):Void
	{	
		//trace("Buffer.updateElement at position" + element.bytePos);
		if (element.bytePos == -1) throw ("Error, Element is not added to Buffer");		
		if (_gl != null) element.updateGLBuffer(_gl, _glBuffer, _elemBuffSize);
	}
	
	/**
        Adds an element to the buffer and renderers it.
        @param  element Element instance to add
    **/
	public function addElement(element: $elementType):Void
	{	
		if (element.bytePos == -1) {
			element.bytePos = _maxElements * _elemBuffSize;
			element.dataPointer = new peote.view.PeoteGL.BytePointer(_bytes, element.bytePos);
			//trace("Buffer.addElement", _maxElements, element.bytePos);
			_elements.set(_maxElements++, element);
			updateElement(element);		
		} 
		else throw("Error: Element is already inside a Buffer");
	}
		
	/**
        Removes an element from the buffer so it did nor renderer anymore.
        @param  element Element instance to remove
    **/
	public function removeElement(element: $elementType):Void
	{
		if (element.bytePos != -1) {
			if (_maxElements > 1 && element.bytePos < (_maxElements-1) * _elemBuffSize ) {
				trace("Buffer.removeElement", element.bytePos);
				var lastElement: $elementType = _elements.get(--_maxElements);
				lastElement.bytePos = element.bytePos;
				lastElement.dataPointer = new peote.view.PeoteGL.BytePointer(_bytes, element.bytePos);
				updateElement(lastElement);
				_elements.set( Std.int(  element.bytePos / _elemBuffSize ), lastElement);
			}
			else _maxElements--;
			element.bytePos = -1;			
		}
		else throw("Error: Element is not inside a Buffer");
	}

	// TODO: if alpha + zIndex this will be needed 
	/*public function sortTransparency():Void
	{
	}*/
	
	private inline function getVertexShader():String return $p{elemField}.vertexShader;
	private inline function getFragmentShader():String return $p{elemField}.fragmentShader;
	private inline function getTextureIdentifiers():Array<String> return ($p{elemField}.IDENTIFIERS_TEXTURE == "") ? [] : $p{elemField}.IDENTIFIERS_TEXTURE.split(",");
	private inline function getColorIdentifiers():Array<String> return ($p{elemField}.IDENTIFIERS_COLOR == "") ? [] :  $p{elemField}.IDENTIFIERS_COLOR.split(",");
	private inline function getDefaultColorFormula():String return $p{elemField}.DEFAULT_COLOR_FORMULA;
	private inline function getDefaultFormulaVars():haxe.ds.StringMap<peote.view.Color> return $p{elemField}.DEFAULT_FORMULA_VARS;
	private inline function hasAlpha():Bool return $p{elemField}.ALPHA_ENABLED;
	private inline function hasZindex():Bool return $p{elemField}.ZINDEX_ENABLED;
	private inline function hasPicking():Bool return $p{elemField}.PICKING_ENABLED;
	private inline function needFragmentPrecision():Bool return $p{elemField}.NEED_FRAGMENT_PRECISION;

	private inline function bindAttribLocations(gl: peote.view.PeoteGL, glProgram: peote.view.PeoteGL.GLProgram):Void
	{
		if (peote.view.PeoteGL.Version.isINSTANCED)
			$p{elemField}.bindAttribLocationsInstanced(gl, glProgram);
		else $p{elemField}.bindAttribLocations(gl, glProgram);
	}
	
	/**
        Gets the element at screen position.
        @param  program the program this buffer is bind to
    **/
	public function pickElementAt(x:Int, y:Int, program:peote.view.Program ): $elementType
	{
		//var elementNumber:Int = program.pickElementAt(x, y);
		//trace("---------PICKED elementNumber:" + elementNumber);
		return null;//TODO
	}

	private inline function render(peoteView:peote.view.PeoteView, display:peote.view.Display, program:peote.view.Program)
	{		
		//trace("        ---buffer.render---");
		#if peoteview_queueGLbuffering
		//TODO: put all in one glCommandQueue (+ loop)
		if (updateGLBufferElementQueue.length > 0) _updateElement(updateGLBufferElementQueue.shift());
		if (setNewGLContextQueue.length > 0) _setNewGLContext(setNewGLContextQueue.shift());
		/*if (queueDeleteGLBuffer) {
			queueDeleteGLBuffer = false;
			_deleteGLBuffer();
		}
		if (queueCreateGLBuffer) {
			queueCreateGLBuffer = false;
			_createGLBuffer();
		}
		if (queueUpdateGLBuffer) {
			queueUpdateGLBuffer = false;
			_updateGLBuffer();
		}*/
		#end
		
		//var t = haxe.Timer.stamp();
		if (peote.view.PeoteGL.Version.isINSTANCED) {
			if (peote.view.PeoteGL.Version.isVAO) _gl.bindVertexArray(_glVAO);
			else $p{elemField}.enableVertexAttribInstanced(_gl, _glBuffer, _glInstanceBuffer);
			
			_gl.drawArraysInstanced (_gl.TRIANGLE_STRIP,  0, $p{elemField}.VERTEX_COUNT, _maxElements);
			
			if (peote.view.PeoteGL.Version.isVAO) _gl.bindVertexArray(null);
			else $p{elemField}.disableVertexAttribInstanced(_gl);
			
			_gl.bindBuffer (_gl.ARRAY_BUFFER, null); // TODO: check if this is obsolete on all platforms !
		}
		else {
			if (peote.view.PeoteGL.Version.isVAO) _gl.bindVertexArray(_glVAO);
			else $p{elemField}.enableVertexAttrib(_gl, _glBuffer);
			
			_gl.drawArrays (_gl.TRIANGLE_STRIP,  0, _maxElements * $p{elemField}.VERTEX_COUNT);
			
			if (peote.view.PeoteGL.Version.isVAO) _gl.bindVertexArray(null);
			else $p{elemField}.disableVertexAttrib(_gl);
			
			_gl.bindBuffer (_gl.ARRAY_BUFFER, null); // TODO: check if this is obsolete on all platforms !
		}
		//trace("render time:"+(haxe.Timer.stamp()-t));
	}

	
};



// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------			
			//Context.defineModule(classPackage.concat([className]).join('.'),[c],Context.getLocalImports());
			Context.defineModule(classPackage.concat([className]).join('.'),[c]);
			//Context.defineType(c);
		}
		return TPath({ pack:classPackage, name:className, params:[] });
	}
}
#end
