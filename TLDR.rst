Luminance
=========
Here are two ways to define Luminance:

1. Photometric/digital `ITU BT.709 <https://www.itu.int/rec/R-REC-BT.709>`_:
    **Formula:** :math:`0.2126\times R + 0.7152\times G + 0.0722\times B`

.. image:: ./imgs/BT709.png
    
2. Digital `ITU BT.601 <http://www.itu.int/rec/R-REC-BT.601>`_ (more weight to the R and B):
    **Formula:** :math:`0.299\times R + 0.587\times G + 0.114\times B`

.. image:: ./imgs/BT601.png
    
References:

- `Luma (Wikipedia) <http://en.wikipedia.org/wiki/Luma_(video)>`_
- `Relative Luminance (Wikipedia) <https://en.wikipedia.org/wiki/Relative_luminance>`_
- `Color Contrast (w3.org) <https://www.w3.org/TR/AERT/#color-contrast>`_
- `Stackoverflow post <https://stackoverflow.com/questions/596216/formula-to-determine-perceived-brightness-of-rgb-color>`_

Scale factor
============
References:

- `[pdf] Greg Ward, A Contrast-Based Scalefactor for Luminance Display <https://wem.lbl.gov/sites/all/files/lbl-35252.pdf>`_
  
Gamma Correction
================
References:

- `Gamma Correction (Wikipedia) <https://en.wikipedia.org/wiki/Gamma_correction>`_
- `Gamma Correction (Cambridge in Colour) <https://www.cambridgeincolour.com/tutorials/gamma-correction.htm>`_
