package ui.modal.dialog;

import data.DataTypes;

class RuleEditor extends ui.modal.Dialog {
	var curValue = -1;
	var layerDef : data.def.LayerDef;
	var sourceDef : data.def.LayerDef;
	var rule : data.def.AutoLayerRuleDef;
	var guidedMode = false;

	public function new(layerDef:data.def.LayerDef, rule:data.def.AutoLayerRuleDef) {
		super("ruleEditor");

		setTransparentMask();
		this.layerDef = layerDef;
		this.rule = rule;
		sourceDef = layerDef.type==IntGrid ? layerDef : project.defs.getLayerDef( layerDef.autoSourceLayerDefUid );

		// Smart pick current IntGrid value
		curValue = -1;
		var counts = new Map();
		var best = -1;
		for(cy in 0...rule.size)
		for(cx in 0...rule.size) {
			var v = M.iabs( rule.get(cx,cy) );
			if( v==0 || v==Const.AUTO_LAYER_ANYTHING )
				continue;

			if( !counts.exists(v) )
				counts.set(v,1);
			else
				counts.set(v,counts.get(v)+1);

			if( best<0 || counts.get(best)<counts.get(v) )
				best = v;
		}
		curValue = best;

		// Default current value
		if( curValue<0 )
			for(iv in sourceDef.getAllIntGridValues()) {
				curValue = iv.value;
				break;
			}
		if( curValue==-1 )
			curValue = Const.AUTO_LAYER_ANYTHING;

		renderAll();
	}

	override function onGlobalEvent(e:GlobalEvent) {
		super.onGlobalEvent(e);
		switch(e) {
			case LayerRuleChanged(rule):

			case _:
		}
	}

	function enableGuidedMode() {
		guidedMode = true;
		jContent.addClass("guided");
		jContent.find(".disableTip").removeClass("disableTip");
		jContent.find(".explain").show();
	}


	override function close() {
		super.close();

		if( rule.isEmpty() ) {
			for(rg in layerDef.autoRuleGroups)
				rg.rules.remove(rule);
			editor.ge.emit( LayerRuleRemoved(rule) );
		}
		else if( rule.tidy(layerDef) )
			editor.ge.emit( LayerRuleChanged(rule) );
	}


	function updateTileSettings() {
		var jTilesSettings = jContent.find(".tileSettings");
		jTilesSettings.off();

		// Tile mode
		var jModeSelect = jContent.find("select[name=tileMode]");
		jModeSelect.empty();
		var i = new form.input.EnumSelect(
			jModeSelect,
			ldtk.Json.AutoLayerRuleTileMode,
			()->rule.tileMode,
			(v)->rule.tileMode = v,
			(v)->switch v {
				case Single: Lang.t._("Random tiles");
				case Stamp: Lang.t._("Rectangle of tiles");
			}
		);
		i.linkEvent( LayerRuleChanged(rule) );
		i.onChange = function() {
			rule.tileIds = [];
			updateTileSettings();
		}

		// Tile(s)
		var jTilePicker = JsTools.createTilePicker(
			Editor.ME.curLayerInstance.getTilesetUid(),
			rule.tileMode==Single?Free:RectOnly,
			rule.tileIds,
			false,
			function(tids) {
				rule.tileIds = tids.copy();
				editor.ge.emit( LayerRuleChanged(rule) );
				updateTileSettings();
			}
		);
		jTilesSettings.find(">.picker").empty().append( jTilePicker );

		// Pivot (optional)
		var jTileOptions = jTilesSettings.find(">.options").empty();
		switch rule.tileMode {
			case Single:
			case Stamp:
				var jPivot = JsTools.createPivotEditor(rule.pivotX, rule.pivotY, (xr,yr)->{
					rule.pivotX = xr;
					rule.pivotY = yr;
					editor.ge.emit( LayerRuleChanged(rule) );
					renderAll();
				});
				jTileOptions.append(jPivot);
		}
	}



	function updateValuePalette() {
		var jValuePalette = jContent.find(">.pattern .valuePalette>ul").empty();

		// Values view mode
		var stateId = settings.makeStateId(RuleValuesColumns, layerDef.uid);
		var columns = settings.getUiStateInt(stateId, project, 1);
		JsTools.removeClassReg(jValuePalette, ~/col-[0-9]+/g);
		jValuePalette.addClass("col-"+columns);

		// View select
		var jMode = jContent.find(".displayMode");
		jMode.off().click(_->{
			var m = new ContextMenu(jMode);
			m.add({
				label:L.t._("List"),
				icon: "listView",
				cb: ()->{
					settings.deleteUiState(stateId, project);
					updateValuePalette();
				}
			});
			for(n in [2,3,4,5]) {
				m.add({
					label:L.t._("::n:: columns", {n:n}),
					icon: "gridView",
					cb: ()->{
						settings.setUiStateInt(stateId, n, project);
						updateValuePalette();
					}
				});
			}
		});

		// Groups
		for(g in sourceDef.getGroupedIntGridValues()) {
			var groupValue = (g.groupUid+1)*1000;

			var jHeader = new J('<li class="title"/>');
			jHeader.append('<span class="icon folderClose"/>');
			if( sourceDef.hasIntGridGroups() ) {
				jHeader.appendTo(jValuePalette);
				jHeader.append('<span class="name">${g.displayName}</span>');

				jHeader.click(_->{
					curValue = groupValue;
					updateValuePalette();
				});
			}

			var jSubList = new J('<li class="subList"> <ul class="groupValues"></ul> </li>');
			jSubList.appendTo(jValuePalette);

			if( g.color!=null ) {
				var alpha = curValue==groupValue ? 1 : 0.4;
				jHeader.css("background-color", g.color.toCssRgba(0.8*alpha));
				jSubList.css("background-color", g.color.toCssRgba(0.5*alpha));
			}

			if( curValue==groupValue )
				jHeader.add(jSubList).addClass("active");

			// Individual values
			jSubList = jSubList.find("ul");
			for(v in g.all) {
				var jVal = new J('<li class="value"/>');
				jVal.appendTo(jSubList);
				jVal.css("background-color", C.intToHex(v.color));
				jVal.append( JsTools.createIntGridValue(project, v, false) );
				jVal.append('<span class="name">${v.identifier!=null ? v.identifier : Std.string(v.value)}</span>');
				jVal.find(".name").css("color", C.intToHex( C.autoContrast(v.color) ) );

				if( curValue==v.value )
					jVal.addClass("active");

				var id = v.value;
				jVal.click( function(ev) {
					curValue = id;
					updateValuePalette();
				});
			}
		}

		// "Anything" value
		var jVal = new J('<li/>');
		jVal.appendTo(jValuePalette);
		jVal.addClass("any");
		jVal.append('<span class="value"></span>');
		var label = '"Any value" / "No value"';
		jVal.append('<span class="name">$label</span>');
		if( curValue==Const.AUTO_LAYER_ANYTHING )
			jVal.addClass("active");
		jVal.click( function(ev) {
			curValue = Const.AUTO_LAYER_ANYTHING;
			editor.ge.emit( LayerRuleChanged(rule) );
			updateValuePalette();
		});


		// Value groups
		// var jGroups = jContent.find(">.pattern .groups ul").empty();
		// // JsTools.removeClassReg(jGroups, ~/col-[0-9]+/g);
		// // jGroups.addClass("col-"+columns);
		// for(g in sourceDef.getGroupedIntGridValues())
		// 	jGroups.append('<li>${g.displayName}</li>');
	}

	function renderAll() {

		loadTemplate("ruleEditor");
		jContent.find("[data-title],[title]").addClass("disableTip"); // removed on guided mode

		// Mini explanation tip
		var jExplain = jContent.find(".explain").hide();

		// Guided mode button
		jContent.find("button.guide").click( (_)->{
			enableGuidedMode();
		} );
		jContent.find(".debugInfos").text('#${rule.uid}');

		updateTileSettings();

		// Pattern grid editor
		var patternEditor = new RulePatternEditor(
			rule, sourceDef, layerDef,
			(str:String)->{
				if( str==null )
					jExplain.empty();
				else {
					if( str.indexOf("\\n")>=0 )
						str = "<p>" + str.split("\\n").join("</p><p>") + "</p>";
					jExplain.html(str);
				}
			},
			()->curValue,
			()->editor.ge.emit( LayerRuleChanged(rule) )
		);
		jContent.find(">.pattern .editor .grid").empty().append( patternEditor.jRoot );


		// Grid size selection
		var jSizes = jContent.find(">.pattern .editor select").empty();
		var s = -1;
		var sizes = [ while( s<Const.MAX_AUTO_PATTERN_SIZE ) s+=2 ];
		for(size in sizes) {
			var jOpt = new J('<option value="$size">${size}x$size</option>');
			jOpt.appendTo(jSizes);
		}
		jSizes.change( function(_) {
			var size = Std.parseInt( jSizes.val() );
			rule.resize(size);
			editor.ge.emit( LayerRuleChanged(rule) );
			renderAll();
		});
		jSizes.val(rule.size);

		// Out-of-bounds policy
		var jOutOfBounds = jContent.find("#outOfBoundsValue");
		JsTools.createOutOfBoundsRulePolicy(jOutOfBounds, sourceDef, rule.outOfBoundsValue, (v)->{
			rule.outOfBoundsValue = v;
			editor.ge.emit( LayerRuleChanged(rule) );
			renderAll();
		});

		// Finalize
		updateValuePalette();
		if( guidedMode )
			enableGuidedMode();

		JsTools.parseComponents(jContent);
	}

}