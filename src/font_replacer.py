"""Replace fonts in a PPTX file."""
from __future__ import annotations

from pptx import Presentation
from pptx.oxml.ns import qn
from lxml import etree
import copy
import os


def replace_fonts_in_pptx(pptx_path: str, replacements: dict[str, str], output_path: str) -> str:
    """
    Replace fonts in a PPTX file.

    Args:
        pptx_path:    Path to the source PPTX.
        replacements: Dict mapping old font name → new font name.
        output_path:  Where to write the modified PPTX.

    Returns:
        output_path
    """
    if not replacements:
        import shutil
        shutil.copy2(pptx_path, output_path)
        return output_path

    prs = Presentation(pptx_path)

    def _replace_in_element(elem):
        """Recursively replace font names in XML element attributes."""
        # <a:rPr> has typeface in <a:latin>, <a:ea>, <a:cs> children
        # and also directly via the 'lang' attribute sometimes
        for tag in (qn("a:latin"), qn("a:ea"), qn("a:cs"), qn("a:sym")):
            for node in elem.iter(tag):
                typeface = node.get("typeface")
                if typeface and typeface in replacements:
                    node.set("typeface", replacements[typeface])

        # Theme fonts in <a:bodyPr> defaultTabSize etc. are fine to ignore.
        # Also handle <p:txStyles> in slide masters
        for tag in (qn("a:defRPr"), qn("a:rPr"), qn("a:endParaRPr")):
            for node in elem.iter(tag):
                for child_tag in (qn("a:latin"), qn("a:ea"), qn("a:cs")):
                    for child in node.iter(child_tag):
                        tf = child.get("typeface")
                        if tf and tf in replacements:
                            child.set("typeface", replacements[tf])

    # Process all slides
    for slide in prs.slides:
        _replace_in_element(slide._element)

    # Process slide layouts
    for layout in prs.slide_layouts:
        _replace_in_element(layout._element)

    # Process slide masters
    for master in prs.slide_masters:
        _replace_in_element(master._element)

    prs.save(output_path)
    return output_path
