haxe -xml doc/api/doc.xml \
	-cp src -lib lime -D doc-gen \
	--no-output -neko dummy.n \
	peote.view.PeoteView
	
haxelib run dox \
	-i doc/api/doc.xml \
	-o doc/api \
	--toplevel-package peote.view

rm doc/api/doc.xml