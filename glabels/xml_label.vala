/*  xml_label.vala
 *
 *  Copyright (C) 2012  Jim Evins <evins@snaught.com>
 *
 *  This file is part of gLabels.
 *
 *  gLabels is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  gLabels is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with gLabels.  If not, see <http://www.gnu.org/licenses/>.
 */


using GLib;
using libglabels;

namespace glabels
{

	namespace XmlLabel
	{

		public errordomain XmlError
		{
			OPEN_ERROR,
			UNKNOWN_MEDIA,
			PARSE_ERROR,
			SAVE_ERROR
		}

		/* TODO: pull HUGE from libxml vapi file when available. */
		const int MY_XML_PARSE_HUGE = 1 << 19;


		public Label open_file( string utf8_filename ) throws XmlError
		{

			string filename;
			try
			{
				filename = Filename.from_utf8( utf8_filename, -1, null, null );
			}
			catch ( ConvertError e )
			{
				throw new XmlError.OPEN_ERROR( "Utf8 filename conversion error." );
			}

			unowned Xml.Doc* doc = Xml.Parser.read_file( filename, null, MY_XML_PARSE_HUGE );
			if ( doc == null )
			{
				throw new XmlError.PARSE_ERROR( "xmlReadFile error." );
			}

			/* TODO:
			xmlXIncludeProcess (doc);
			xmlReconciliateNs (doc, xmlDocGetRootElement (doc));
			*/

			Label label = parse_doc( doc );
			label.filename = filename;

			return label;
		}


		public Label open_buffer( string buffer ) throws XmlError
		{

			unowned Xml.Doc* doc = Xml.Parser.read_doc( buffer, null, null, MY_XML_PARSE_HUGE );
			if ( doc == null )
			{
				throw new XmlError.PARSE_ERROR( "xmlReadDoc error." );
			}

			Label? label = parse_doc( doc );

			return label;
		}


		private Label parse_doc( Xml.Doc doc ) throws XmlError
		{
			unowned Xml.Node* root = doc.get_root_element();
			if ( (root == null) || (root->name == null) ) {
				throw new XmlError.PARSE_ERROR( "No document root." );
			}

#if TODO
			/* Try compatability mode 0.4 */
			if (xmlSearchNsByHref (doc, root, (xmlChar *)COMPAT04_NAME_SPACE))
			{
				message( "Importing from glabels 0.4 format" );
				return gl_xml_label_04_parse( root, status );
			}

			/* Test for current namespaces. */
			if ( !xmlSearchNsByHref (doc, root, (xmlChar *)COMPAT20_NAME_SPACE) &&
			     !xmlSearchNsByHref (doc, root, (xmlChar *)COMPAT22_NAME_SPACE) &&
			     !xmlSearchNsByHref (doc, root, (xmlChar *)LGL_XML_NAME_SPACE) )
			{
				message( "Unknown glabels Namespace -- Using %s", XML_NAME_SPACE );
			}
#endif

			if ( root->name != "Glabels-document" )
			{
				throw new XmlError.PARSE_ERROR( "Root node != \"Glabels-document\"." );
			}

			Label label = parse_glabels_document_node( root );
			label.compression = doc.get_compress_mode();

			return label;
		}


		private Label parse_glabels_document_node( Xml.Node node ) throws XmlError
		{
			Label label = new Label();

			/* Pass 1, extract data nodes to pre-load cache. */
			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				if ( child->name == "Data" )
				{
					parse_data_node( child, label );
				}
			}

			/* Pass 2, now extract everything else. */
			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				switch (child->name)
				{

				case "Template":
					Template? template = XmlTemplate.parse_template_node( child );
					if ( template == null )
					{
						throw new XmlError.PARSE_ERROR( "Bad template." );
					}
					label.template = template;
					break;

				case "Objects":
					parse_objects_node( child, label );
					break;

				case "Merge":
					parse_merge_node( child, label );
					break;

				case "Data":
					/* Handled in pass 1. */
					break;

				default:
					if ( child->is_text() == 0 )
					{
						message( "Unexpected %s child: \"%s\"", node.name, child->name );
					}
					break;
				}
			}

			return label;
		}


		private void parse_objects_node( Xml.Node node,
		                                 Label    label )
		{
			label.rotate = XmlUtil.get_prop_bool( node, "rotate", false );

			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				switch (child->name)
				{

				case "Object-box":
					parse_object_box_node( child, label );
					break;

				case "Object-ellipse":
					parse_object_ellipse_node( child, label );
					break;

				case "Object-line":
					parse_object_line_node( child, label );
					break;

				case "Object-image":
					parse_object_image_node( child, label );
					break;

				case "Object-barcode":
					parse_object_barcode_node( child, label );
					break;

				case "Object-text":
					parse_object_text_node( child, label );
					break;

				default:
					if ( child->is_text() == 0 )
					{
						message( "Unexpected %s child: \"%s\"", node.name, child->name );
					}
					break;
				}
			}

		}


		private void parse_object_box_node( Xml.Node node,
		                                    Label    label )
		{
			LabelObjectBox object = new LabelObjectBox.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* size attrs */
			object.w = XmlUtil.get_prop_length( node, "w", 0 );
			object.h = XmlUtil.get_prop_length( node, "h", 0 );

			/* line attrs */
			object.line_width = XmlUtil.get_prop_length( node, "line_width", 1.0 );
	
			{
				string key        = XmlUtil.get_prop_string( node, "line_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "line_color", 0 ) );
				object.line_color_node = ColorNode( field_flag, color, key );
			}

			/* fill attrs */
			{
				string key        = XmlUtil.get_prop_string( node, "fill_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "fill_color", 0 ) );
				object.fill_color_node = ColorNode( field_flag, color, key );
			}
	
			/* affine attrs */
			parse_affine_attrs( node, object );

			/* shadow attrs */
			parse_shadow_attrs( node, object );
		}


		private void parse_object_ellipse_node( Xml.Node node,
		                                        Label    label )
		{
			LabelObjectEllipse object = new LabelObjectEllipse.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* size attrs */
			object.w = XmlUtil.get_prop_length( node, "w", 0 );
			object.h = XmlUtil.get_prop_length( node, "h", 0 );

			/* line attrs */
			object.line_width = XmlUtil.get_prop_length( node, "line_width", 1.0 );
	
			{
				string key        = XmlUtil.get_prop_string( node, "line_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "line_color", 0 ) );
				object.line_color_node = ColorNode( field_flag, color, key );
			}

			/* fill attrs */
			{
				string key        = XmlUtil.get_prop_string( node, "fill_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "fill_color", 0 ) );
				object.fill_color_node = ColorNode( field_flag, color, key );
			}
	
			/* affine attrs */
			parse_affine_attrs( node, object );

			/* shadow attrs */
			parse_shadow_attrs( node, object );
		}


		private void parse_object_line_node( Xml.Node node,
		                                     Label    label )
		{
			LabelObjectLine object = new LabelObjectLine.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* size attrs */
			object.w = XmlUtil.get_prop_length( node, "dx", 0 );
			object.h = XmlUtil.get_prop_length( node, "dy", 0 );

			/* line attrs */
			object.line_width = XmlUtil.get_prop_length( node, "line_width", 1.0 );
	
			{
				string key        = XmlUtil.get_prop_string( node, "line_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "line_color", 0 ) );
				object.line_color_node = ColorNode( field_flag, color, key );
			}

			/* affine attrs */
			parse_affine_attrs( node, object );

			/* shadow attrs */
			parse_shadow_attrs( node, object );
		}


		private void parse_object_image_node( Xml.Node node,
		                                      Label    label )
		{
			LabelObjectImage object = new LabelObjectImage.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* src or field attrs */
			string src = XmlUtil.get_prop_string( node, "src", null );
			if ( src != null )
			{
				object.filename_node = new TextNode( false, src );
			}
			else
			{
				string field = XmlUtil.get_prop_string( node, "field", null );
				if ( field != null )
				{
					object.filename_node = new TextNode( true, field );
				}
				else
				{
					message( "Missing Object-image src or field attr" );
				}
			}
					
			/* size attrs, must be set after filename because setting filename may adjust these. */
			object.w = XmlUtil.get_prop_length( node, "w", 0 );
			object.h = XmlUtil.get_prop_length( node, "h", 0 );

			/* affine attrs */
			parse_affine_attrs( node, object );

			/* shadow attrs */
			parse_shadow_attrs( node, object );
		}


		private void parse_object_barcode_node( Xml.Node node,
		                                        Label    label )
		{
			LabelObjectBarcode object = new LabelObjectBarcode.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* size attrs */
			object.w = XmlUtil.get_prop_length( node, "w", 0 );
			object.h = XmlUtil.get_prop_length( node, "h", 0 );

			/* style attrs */
			string backend_id = XmlUtil.get_prop_string( node, "backend", null );
			string style_id   = XmlUtil.get_prop_string( node, "style", "Code39" );
			if ( (backend_id != null) && (backend_id != "built-in") )
			{
				object.bc_style = BarcodeBackends.lookup_style_from_id( "%s:%s".printf( backend_id, style_id ) );
			}
			else
			{
				object.bc_style = BarcodeBackends.lookup_style_from_id( style_id );
			}
			object.bc_text_flag     = XmlUtil.get_prop_bool( node, "text", false );
			object.bc_checksum_flag = XmlUtil.get_prop_bool( node, "checksum", true );
			object.bc_format_digits = XmlUtil.get_prop_int(  node, "format", 10 );
					
			/* color attrs */
			{
				string key        = XmlUtil.get_prop_string( node, "color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "color", 0 ) );
				object.bc_color_node = ColorNode( field_flag, color, key );
			}

			/* data attrs */
			string data = XmlUtil.get_prop_string( node, "data", null );
			if ( data != null )
			{
				object.bc_data_node = new TextNode( false, data );
			}
			else
			{
				string field = XmlUtil.get_prop_string( node, "field", null );
				if ( field != null )
				{
					object.bc_data_node = new TextNode( true, field );
				}
				else
				{
					message( "Missing Object-barcode data or field attr." );
				}
			}
	
			/* affine attrs */
			parse_affine_attrs( node, object );
		}


		private void parse_object_text_node( Xml.Node node,
		                                     Label    label )
		{
			LabelObjectText object = new LabelObjectText.with_parent( label );

		
			/* position attrs */
			object.x0 = XmlUtil.get_prop_length( node, "x", 0.0 );
			object.y0 = XmlUtil.get_prop_length( node, "y", 0.0 );

			/* size attrs */
			object.w = XmlUtil.get_prop_length( node, "w", 0 );
			object.h = XmlUtil.get_prop_length( node, "h", 0 );

			/* align attr */
			object.text_alignment = EnumUtil.string_to_align( XmlUtil.get_prop_string( node, "align", "left" ) );

			/* valign attr */
			object.text_valignment = EnumUtil.string_to_valign( XmlUtil.get_prop_string( node, "valign", "top" ) );

			/* auto_shrink attr */
			object.auto_shrink = XmlUtil.get_prop_bool( node, "auto_shrink", false );

			/* affine attrs */
			parse_affine_attrs( node, object );

			/* shadow attrs */
			parse_shadow_attrs( node, object );

			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				switch (child->name)
				{
				case "Span":
					parse_toplevel_span_node( child, object );
					break;

				default:
					if ( child->is_text() == 0 )
					{
						message( "Unexpected %s child: \"%s\"", node.name, child->name );
					}
					break;
				}
			}
		}


		private void parse_toplevel_span_node( Xml.Node        node,
		                                       LabelObjectText object )
		{
			/* font_family attr */
			object.font_family = XmlUtil.get_prop_string( node, "font_family", "Sans" );

			/* font_size attr */
			object.font_size = XmlUtil.get_prop_double( node, "font_size", 12.0 );

			/* font_weight attr */
			object.font_weight = EnumUtil.string_to_weight( XmlUtil.get_prop_string( node, "font_weight", "normal" ) );

			/* font_italic attr */
			object.font_italic_flag = XmlUtil.get_prop_bool( node, "font_italic", false );

			/* color attrs */
			string color_field_string = XmlUtil.get_prop_string( node, "color_field", null );
			if ( color_field_string != null )
			{
				object.text_color_node = ColorNode.from_key( color_field_string );
			}
			else
			{
				object.text_color_node = ColorNode.from_legacy_color( XmlUtil.get_prop_uint( node, "color", 0 ) );
			}

			/* line_spacing attr */
			object.text_line_spacing = XmlUtil.get_prop_double( node, "line_spacing", 1 );

			/* Now descend children and build lines of text nodes */
			TextLines lines = new TextLines();
			TextLine  line  = new TextLine();
			Regex strip_regex = new Regex( "\\A\\n\\s*|\\n\\s*\\Z" );
			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				switch (child->name)
				{
				case "Span":
					message( "Unexpected rich text (not supported, yet!)" );
					break;

				case "Field":
					line.append( new TextNode( true, XmlUtil.get_prop_string( child, "name", null ) ) );
					break;

				case "NL":
					lines.append( line );
					line = new TextLine();
					break;

				default:
					if ( child->is_text() != 0 )
					{
						/* Literal text. */
						string raw_data = child->get_content();
						string data = strip_regex.replace( raw_data, -1, 0, "" );
						line.append( new TextNode( false, data ) );
					}
					else
					{
						message( "Unexpected %s child: \"%s\"", node.name, child->name );
					}
					break;
				}
			}
			if ( !line.empty() )
			{
				lines.append( line );
			}
			object.set_lines( lines );
		}


		private void parse_affine_attrs( Xml.Node    node,
		                                 LabelObject object )
		{
			double           a[6];

			a[0] = XmlUtil.get_prop_double( node, "a0", 0.0 );
			a[1] = XmlUtil.get_prop_double( node, "a1", 0.0 );
			a[2] = XmlUtil.get_prop_double( node, "a2", 0.0 );
			a[3] = XmlUtil.get_prop_double( node, "a3", 0.0 );
			a[4] = XmlUtil.get_prop_double( node, "a4", 0.0 );
			a[5] = XmlUtil.get_prop_double( node, "a5", 0.0 );

			object.matrix = Cairo.Matrix( a[0], a[1], a[2], a[3], a[4], a[5] );
		}


		private void parse_shadow_attrs( Xml.Node    node,
		                                 LabelObject object )
		{
			object.shadow_state = XmlUtil.get_prop_bool( node, "shadow", false );

			if (object.shadow_state)
			{
				object.shadow_x = XmlUtil.get_prop_length( node, "shadow_x", 0.0 );
				object.shadow_y = XmlUtil.get_prop_length( node, "shadow_y", 0.0 );
		
				string key        = XmlUtil.get_prop_string( node, "shadow_color_field", null );
				bool   field_flag = key != null;
				Color  color      = Color.from_legacy_color( XmlUtil.get_prop_uint( node, "shadow_color", 0 ) );
				object.shadow_color_node = ColorNode( field_flag, color, key );

				object.shadow_opacity = XmlUtil.get_prop_double( node, "shadow_opacity", 1.0 );
			}
		}


		private void parse_merge_node( Xml.Node  node,
		                               Label     label )
		{
			Merge merge = MergeBackends.create_merge( XmlUtil.get_prop_string( node, "type", null ) );

			merge.src  = XmlUtil.get_prop_string( node, "src", null );

			label.merge = merge;
		}


		private void parse_data_node( Xml.Node  node,
		                              Label     label )
		{

			for ( unowned Xml.Node* child = node.children; child != null; child = child->next )
			{
				switch (child->name)
				{

				case "Pixdata":
					parse_pixdata_node( child, label );
					break;

				case "File":
					parse_file_node( child, label );
					break;

				default:
					if ( child->is_text() == 0 )
					{
						message( "Unexpected %s child: \"%s\"", node.name, child->name );
					}
					break;

				}
			}

		}


		private void parse_pixdata_node( Xml.Node  node,
		                                 Label     label )
		{
			string name = XmlUtil.get_prop_string( node, "name", null );
			string base64 = node.get_content();

			uchar[] stream = Base64.decode( base64 );
			Gdk.Pixdata pixdata = Gdk.Pixdata();
			if ( pixdata.deserialize( stream ) )
			{
				Gdk.Pixbuf pixbuf = Gdk.Pixbuf.from_pixdata( pixdata, true );
				label.pixbuf_cache.add_pixbuf( name, pixbuf );
			}
		}


		private void parse_file_node( Xml.Node  node,
		                              Label     label )
		{
			string name   = XmlUtil.get_prop_string( node, "name",   null );
			string format = XmlUtil.get_prop_string( node, "format", null );

			if ( (format == "SVG") || (format == "Svg") || (format == "svg") )
			{
				string content = node.get_content();
				label.svg_cache.add_svg( name, content );
			}
			else
			{
				message( "Unknown embedded file format: \"%s\"", format );
			}
		}


		public void save_file( Label label,
		                       string utf8_filename ) throws XmlError
		{
			Xml.Doc doc = create_doc( label );

			string filename;
			try
			{
				filename = Filename.from_utf8( utf8_filename, -1, null, null );
			}
			catch ( ConvertError e )
			{
				throw new XmlError.OPEN_ERROR( "Utf8 filename conversion error." );
			}

			if ( doc.save_format_file( filename, 1 ) < 0 )
			{
				throw new XmlError.SAVE_ERROR( "Problem saving xml file." );
			}

			label.filename = utf8_filename;
			label.modified = false;
		}


		public void save_buffer( Label      label,
		                         out string buffer ) throws XmlError
		{
			Xml.Doc doc = create_doc( label );

			int length;
			doc.dump_memory( out buffer, out length );
			if ( length <= 0 )
			{
				throw new XmlError.SAVE_ERROR( "Problem saving xml buffer." );
			}

			label.modified = false;
		}


		private Xml.Doc create_doc( Label label )
		{
			Xml.Doc doc = new Xml.Doc( "1.0" );
			unowned Xml.Node* root_node = new Xml.Node( null, "Glabels-document" );
			doc.set_root_element( root_node );
			unowned Xml.Ns *ns = new Xml.Ns( root_node, NAME_SPACE, null );
			root_node->ns = ns;

			XmlTemplate.create_template_node( label.template, root_node, ns );

			create_objects_node( root_node, ns, label );

			if ( !(label.merge is MergeNone) )
			{
				create_merge_node( root_node, ns, label );
			}

			create_data_node( doc, root_node, ns, label );

			return doc;
		}


		private void create_objects_node( Xml.Node root,
		                                  Xml.Ns   ns,
		                                  Label    label )
		{
			unowned Xml.Node *node = root.new_child( ns, "Objects" );

			XmlUtil.set_prop_string( node, "id", "0" );
			XmlUtil.set_prop_bool( node, "rotate", label.rotate );

			foreach ( LabelObject object in label.object_list )
			{
				if ( object is LabelObjectBox )
				{
					create_object_box_node( node, ns, object as LabelObjectBox );
				}
				else if ( object is LabelObjectEllipse )
				{
					create_object_ellipse_node( node, ns, object as LabelObjectEllipse );
				}
				else if ( object is LabelObjectLine )
				{
					create_object_line_node( node, ns, object as LabelObjectLine );
				}
				else if ( object is LabelObjectImage )
				{
					create_object_image_node( node, ns, object as LabelObjectImage );
				}
				else if ( object is LabelObjectBarcode )
				{
					create_object_barcode_node( node, ns, object as LabelObjectBarcode );
				}
				else if ( object is LabelObjectText )
				{
					create_object_text_node( node, ns, object as LabelObjectText );
				}
				else
				{
					message( "Unknown label object." );
				}
			}
		}


		private void create_object_box_node( Xml.Node       parent,
		                                     Xml.Ns         ns,
		                                     LabelObjectBox object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-box" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "w", object.w );
			XmlUtil.set_prop_length( node, "h", object.h );

			/* line attrs */
			XmlUtil.set_prop_length( node, "line_width", object.line_width );
			if ( object.line_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "line_color_field", object.line_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "line_color", object.line_color_node.color.to_legacy_color() );
			}

			/* fill attrs */
			if ( object.fill_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "fill_color_field", object.fill_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "fill_color", object.fill_color_node.color.to_legacy_color() );
			}

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );
		}


		private void create_object_ellipse_node( Xml.Node           parent,
		                                         Xml.Ns             ns,
		                                         LabelObjectEllipse object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-ellipse" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "w", object.w );
			XmlUtil.set_prop_length( node, "h", object.h );

			/* line attrs */
			XmlUtil.set_prop_length( node, "line_width", object.line_width );
			if ( object.line_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "line_color_field", object.line_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "line_color", object.line_color_node.color.to_legacy_color() );
			}

			/* fill attrs */
			if ( object.fill_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "fill_color_field", object.fill_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "fill_color", object.fill_color_node.color.to_legacy_color() );
			}

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );
		}


		private void create_object_line_node( Xml.Node        parent,
		                                      Xml.Ns          ns,
		                                      LabelObjectLine object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-line" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "dx", object.w );
			XmlUtil.set_prop_length( node, "dy", object.h );

			/* line attrs */
			XmlUtil.set_prop_length( node, "line_width", object.line_width );
			if ( object.line_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "line_color_field", object.line_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "line_color", object.line_color_node.color.to_legacy_color() );
			}

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );
		}


		private void create_object_image_node( Xml.Node         parent,
		                                       Xml.Ns           ns,
		                                       LabelObjectImage object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-image" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "w", object.w );
			XmlUtil.set_prop_length( node, "h", object.h );

			/* src or field attr */
			if ( object.filename_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "field", object.filename_node.data );
			}
			else
			{
				XmlUtil.set_prop_string( node, "src", object.filename_node.data );
			}

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );
		}


		private void create_object_barcode_node( Xml.Node        parent,
		                                         Xml.Ns          ns,
		                                         LabelObjectBarcode object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-barcode" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "w", object.w_raw );
			XmlUtil.set_prop_length( node, "h", object.h_raw );

			/* style attrs */
			if ( object.bc_style.backend_id != "" )
			{
				string[] token = object.bc_style.id.split( ":", 2 );
				XmlUtil.set_prop_string( node, "backend", token[0] );
				XmlUtil.set_prop_string( node, "style",   token[1] );
			}
			else
			{
				XmlUtil.set_prop_string( node, "backend", "built-in" );
				XmlUtil.set_prop_string( node, "style",   object.bc_style.id );
			}
			XmlUtil.set_prop_bool( node, "text",     object.bc_text_flag );
			XmlUtil.set_prop_bool( node, "checksum", object.bc_text_flag );

			/* data attrs */
			if ( object.bc_data_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "field",  object.bc_data_node.data );
				XmlUtil.set_prop_int(    node, "format", object.bc_format_digits );
			}
			else
			{
				XmlUtil.set_prop_string( node, "data",  object.bc_data_node.data );
			}

			/* color attrs */
			if ( object.bc_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "color_field", object.bc_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "color", object.bc_color_node.color.to_legacy_color() );
			}

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );
		}


		private void create_object_text_node( Xml.Node        parent,
		                                      Xml.Ns          ns,
		                                      LabelObjectText object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Object-text" );

			/* position attrs */
			XmlUtil.set_prop_length( node, "x", object.x0 );
			XmlUtil.set_prop_length( node, "y", object.y0 );

			/* size attrs */
			XmlUtil.set_prop_length( node, "w", object.w_raw );
			XmlUtil.set_prop_length( node, "h", object.h_raw );

			/* align attr */
			XmlUtil.set_prop_string( node, "align", EnumUtil.align_to_string( object.text_alignment ) );

			/* valign attr */
			XmlUtil.set_prop_string( node, "valign", EnumUtil.valign_to_string( object.text_valignment ) );

			/* auto_shrink attr */
			XmlUtil.set_prop_bool( node, "auto_shrink", object.auto_shrink );

			/* affine attrs */
			create_affine_attrs( node, object );

			/* shadow attrs */
			create_shadow_attrs( node, object );

			/* Add children */
			create_toplevel_span_node( node, ns, object );
		}


		private void create_toplevel_span_node( Xml.Node        parent,
		                                        Xml.Ns          ns,
		                                        LabelObjectText object )
		{
			unowned Xml.Node *node = parent.new_child( ns, "Span" );

			/* font_family attr */
			XmlUtil.set_prop_string( node, "font_family", object.font_family );

			/* font_size attr */
			XmlUtil.set_prop_double( node, "font_size", object.font_size );

			/* font_weight attr */
			XmlUtil.set_prop_string( node, "font_weight", EnumUtil.weight_to_string( object.font_weight ) );

			/* font_italic attr */
			XmlUtil.set_prop_bool( node, "font_italic", object.font_italic_flag );

			/* color attrs */
			if ( object.text_color_node.field_flag )
			{
				XmlUtil.set_prop_string( node, "color_field", object.text_color_node.key );
			}
			else
			{
				XmlUtil.set_prop_uint_hex( node, "color", object.text_color_node.color.to_legacy_color() );
			}

			/* line_spacing attr */
			XmlUtil.set_prop_double( node, "line_spacing", object.text_line_spacing );

			/* Build children */
			TextLines lines = object.get_lines();
			bool first_line = true;
			foreach (TextLine line in lines.lines)
			{
				if ( !first_line )
				{
					node->new_child( ns, "NL" );
				}

				foreach (TextNode text_node in line.nodes)
				{
					if ( text_node.field_flag )
					{
						unowned Xml.Node *child = node->new_child( ns, "Field" );
						XmlUtil.set_prop_string( child, "name", text_node.data );
					}
					else
					{
						node->add_content( text_node.data );
					}
				}

				first_line = false;
			}
			
		}


		private void create_affine_attrs( Xml.Node    node,
		                                  LabelObject object )
		{
			XmlUtil.set_prop_double( node, "a0", object.matrix.xx );
			XmlUtil.set_prop_double( node, "a1", object.matrix.yx );
			XmlUtil.set_prop_double( node, "a2", object.matrix.xy );
			XmlUtil.set_prop_double( node, "a3", object.matrix.yy );
			XmlUtil.set_prop_double( node, "a4", object.matrix.x0 );
			XmlUtil.set_prop_double( node, "a5", object.matrix.y0 );
		}


		private void create_shadow_attrs( Xml.Node    node,
		                                  LabelObject object )
		{
			if ( object.shadow_state )
			{
				XmlUtil.set_prop_bool( node, "shadow", object.shadow_state );

				XmlUtil.set_prop_length( node, "shadow_x", object.shadow_x );
				XmlUtil.set_prop_length( node, "shadow_y", object.shadow_y );

				if ( object.shadow_color_node.field_flag )
				{
					XmlUtil.set_prop_string( node, "shadow_color_field", object.shadow_color_node.key );
				}
				else
				{
					XmlUtil.set_prop_uint_hex( node, "shadow_color", object.shadow_color_node.color.to_legacy_color() );
				}

				XmlUtil.set_prop_double( node, "shadow_opacity", object.shadow_opacity );

			}
		}


		private void create_merge_node( Xml.Node root,
		                                Xml.Ns   ns,
		                                Label    label )
		{
			unowned Xml.Node *node = root.new_child( ns, "Merge" );

			XmlUtil.set_prop_string( node, "type", label.merge.info.id );
			XmlUtil.set_prop_string( node, "src",  label.merge.src );
		}


		private void create_data_node( Xml.Doc  doc,
		                               Xml.Node root,
		                               Xml.Ns   ns,
		                               Label    label )
		{
			unowned Xml.Node *node = root.new_child( ns, "Data" );

			foreach ( string name in label.pixbuf_cache.get_name_list() )
			{
				create_pixdata_node( node, ns, label, name );
			}

			foreach ( string name in label.svg_cache.get_name_list() )
			{
				create_file_svg_node( doc, node, ns, label, name );
			}
		}


		private void create_pixdata_node( Xml.Node root,
		                                  Xml.Ns   ns,
		                                  Label    label,
		                                  string   name )
		{
			Gdk.Pixbuf pixbuf = label.pixbuf_cache.get_pixbuf( name );
			if ( pixbuf != null )
			{
				Gdk.Pixdata pixdata = Gdk.Pixdata();
				Gdk.pixdata_from_pixbuf( out pixdata, pixbuf, false );
				uint8[] stream = pixdata.serialize();
				string base64 = GLib.Base64.encode( stream );
				
				unowned Xml.Node *node = root.new_child( ns, "Pixdata", base64 );
				XmlUtil.set_prop_string( node, "name", name );
				XmlUtil.set_prop_string( node, "encoding", "Base64" );
			}
		}


		private void create_file_svg_node( Xml.Doc  doc,
		                                   Xml.Node root,
		                                   Xml.Ns   ns,
		                                   Label    label,
		                                   string   name )
		{
			string? svg_data = label.svg_cache.get_svg( name );
			if ( svg_data != null )
			{
				unowned Xml.Node *node = root.new_child( ns, "File" );
				XmlUtil.set_prop_string( node, "name", name );
				XmlUtil.set_prop_string( node, "format", "SVG" );

				unowned Xml.Node *cdata_section_node = doc.new_cdata_block( svg_data, svg_data.length );
				node->add_child( cdata_section_node );
			}
		}

	}

}
