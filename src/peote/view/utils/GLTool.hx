package peote.view.utils;

import lime.graphics.opengl.GLRenderbuffer;
import peote.view.PeoteGL.GLFramebuffer;
import peote.view.PeoteGL.GLProgram;
import peote.view.PeoteGL.GLShader;
import peote.view.PeoteGL.GLTexture;
import utils.MultipassTemplate;

class GLTool 
{
	// clear the error-queue
	static public function clearGlErrorQueue(gl:PeoteGL) {
		while ( gl.getError() != gl.NO_ERROR) {}
	}
	
	// fetch last gl-error from queue
	// error-catching can be disabled while context-creation so take care with
	static public function getLastGlError(gl:PeoteGL):Int {
		var err:Int = gl.getError();
		if (err != gl.NO_ERROR) {
			if (err == gl.INVALID_ENUM) trace("(GL-Error: INVALID_ENUM)");
			else if (err == gl.INVALID_VALUE) trace("(GL-Error: INVALID_VALUE)");
			else if (err == gl.INVALID_OPERATION) trace("(GL-Error: INVALID_OPERATION)");
			else if (err == gl.OUT_OF_MEMORY) trace("(GL-Error: OUT_OF_MEMORY)");
			else trace("GL-Error: " + err);
		}
		return err;	
	}
	
	static public inline function createFramebuffer(gl:PeoteGL, texture:GLTexture, depthBuffer:GLRenderbuffer, width:Int, height:Int):GLFramebuffer
	{
		var framebuffer = gl.createFramebuffer();
		
		gl.bindRenderbuffer(gl.RENDERBUFFER, depthBuffer);

		// cpp:DEPTH_COMPONENT // FF/Chrome:DEPTH_COMPONENT24 // IE: DEPTH_COMPONENT16
		clearGlErrorQueue(gl);
		gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, width, height);
		if (getLastGlError(gl) == gl.INVALID_ENUM) {
			trace("switching to DEPTH_COMPONENT16 for framebuffer");
			gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, width, height);
		}
		
		gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
		gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depthBuffer);
		gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);

		if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) throw("Error: Framebuffer not complete!");
		
		gl.bindFramebuffer(gl.FRAMEBUFFER, null);
		gl.bindRenderbuffer(gl.RENDERBUFFER, null);
		
		return (framebuffer);
	}
	
	/*
	static public inline function createFramebufferWithDepthTexture(gl:PeoteGL, texture:GLTexture, depthTexture:GLTexture, width:Int, height:Int):GLFramebuffer
	{
		var framebuffer = gl.createFramebuffer();
		
		gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
		gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
		if (PeoteGL.Version.hasFRAMEBUFFER_DEPTH) {
			depthTexture = TexUtils.createDepthTexture(gl, width, height);
			// TODO: neko sometimes lost its depth (look at RenderToTexture-Sample!)
			gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depthTexture, 0);
		}
		if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) throw("Error: Framebuffer not complete!");
		gl.bindFramebuffer(gl.FRAMEBUFFER, null);
		
		return (framebuffer);
	}
	
	static public function hasFramebufferDepth(gl:PeoteGL):Bool
	{
		var texture = TexUtils.createDepthTexture(gl, 1, 1); // depth-texture did not work here on IE11 with webgl1 (neko/cpp is ok!)
		var fb = gl.createFramebuffer();
		
		gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
		gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, texture, 0);
			
		if (!PeoteGL.Version.isES3) // check only for es2
			if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
				gl.bindFramebuffer(gl.FRAMEBUFFER, null);
				trace("Can not bind depth texture to FB for gl-picking or RenderToTexture");
				texture = null;
				gl.deleteFramebuffer(fb);
				return false;
			}
		gl.bindFramebuffer(gl.FRAMEBUFFER, null);
		
		return true;
	}
	*/
	
	static public inline function compileGLShader(gl:PeoteGL, type:Int, shaderSrc:String, debug:Bool = false):GLShader
	{
		#if peoteview_debug_shader
		if (debug) {
			trace('------ ${(type==gl.VERTEX_SHADER) ? "vertex":"fragment"} shader ------');
			trace("\n"+shaderSrc);
		}
		#end		
		var glShader:GLShader = gl.createShader(type);
		gl.shaderSource(glShader, shaderSrc);
		gl.compileShader(glShader);
		if (gl.getShaderParameter(glShader, gl.COMPILE_STATUS) == 0) {
			throw('ERROR compiling ${(type==gl.VERTEX_SHADER) ? "vertex":"fragment"} shader\n' + gl.getShaderInfoLog(glShader));
			return null;
		} else return glShader;		
	}
	
	static public inline function linkGLProgram(gl:PeoteGL, glProgram:GLProgram):Bool 
	{
		gl.linkProgram(glProgram);

		if (gl.getProgramParameter(glProgram, gl.LINK_STATUS) == 0) // glsl compile error
		{
			throw(gl.getProgramInfoLog(glProgram)
				+ "VALIDATE_STATUS: " + gl.getProgramParameter(glProgram, gl.VALIDATE_STATUS)
				+ "ERROR: " + gl.getError()
			);
			return false;
		}
		else return true;
	}

	static var rComments:EReg = new EReg("//.*?$","gm");
	static var rEmptylines:EReg = new EReg("([ \t]*\r?\n)+", "g");
	static var rStartspaces:EReg = new EReg("^([ \t]*\r?\n)+", "g");

	static public inline function parseShader(shader:String, conf:Dynamic):String {
		var template = new MultipassTemplate(shader);
		return rStartspaces.replace(rEmptylines.replace(template.execute(conf), "\n"), "");
		//return rStartspaces.replace(rEmptylines.replace(rComments.replace(template.execute(conf), ""), "\n"), "");
	}

}