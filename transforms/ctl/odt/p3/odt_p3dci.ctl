// 
// Output Device Transform to P3DCI D60 Simulation
// v0.2.2
//

//
// Summary :
//  This transform is intended for mapping OCES onto a P3 digital cinema 
//  projector that is calibrated to a DCI white point at 48 cd/m^2. The assumed 
//  observer adapted white is D60, and the viewing environment is that of a dark
//  theater. 
//
// Device Primaries : 
//  CIE 1931 chromaticities:  x         y         Y
//              Red:          0.68      0.32
//              Green:        0.265     0.69
//              Blue:         0.15      0.06
//              White:        0.314     0.351     48 cd/m^2
//
// Display EOTF :
//  Gamma: 2.6
//
// Assumed observer adapted white point:
//         CIE 1931 chromaticities:    x            y
//                                     0.32168      0.33767
//
// Viewing Environment:
//  Environment specified in SMPTE RP 431-2-2007
//

import "utilities";
import "utilities-aces";

/* ----- ODT Parameters ------ */
const Chromaticities DISPLAY_PRI = P3DCI_PRI;
const float OCES_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(ACES_PRI,1.0);
const float XYZ_2_DISPLAY_PRI_MAT[4][4] = XYZtoRGB(DISPLAY_PRI,1.0);

const Chromaticities RENDERING_PRI = 
{
  {0.73470, 0.26530},
  {0.00000, 1.00000},
  {0.12676, 0.03521},
  {0.32168, 0.33767}
};
const float XYZ_2_RENDERING_PRI_MAT[4][4] = XYZtoRGB(RENDERING_PRI,1.0);
const float OCES_PRI_2_RENDERING_PRI_MAT[4][4] = mult_f44_f44( OCES_PRI_2_XYZ_MAT, XYZ_2_RENDERING_PRI_MAT);
const float RENDERING_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(RENDERING_PRI,1.0);

// ODT parameters related to black point compensation (BPC) and encoding
const float ODT_OCES_BP = 0.0001;
const float ODT_OCES_WP = 48.0;
const float OUT_BP = 0.0048;
const float OUT_WP = 48.0;

const float DISPGAMMA = 2.6; 
const unsigned int BITDEPTH = 12;
const unsigned int CV_BLACK = 0;
const unsigned int CV_WHITE = pow( 2, BITDEPTH) - 1;
const unsigned int MIN_CV = 0;
const unsigned int MAX_CV = pow( 2, BITDEPTH) - 1;

// Derived BPC and scale parameters
const float BPC = (ODT_OCES_BP * OUT_WP - ODT_OCES_WP * OUT_BP) / 
                  (ODT_OCES_BP - ODT_OCES_WP);
const float SCALE = (OUT_BP - OUT_WP) / (ODT_OCES_BP - ODT_OCES_WP);



void main 
(
  input varying float rIn, 
  input varying float gIn, 
  input varying float bIn, 
  input varying float aIn,
  output varying float rOut,
  output varying float gOut,
  output varying float bOut,
  output varying float aOut
)
{
  // Put input variables (OCES) into a 3-element vector
  float oces[3] = {rIn, gIn, bIn};

  // Convert from OCES to rendering primaries encoding
  float rgbPre[3] = mult_f3_f44( oces, OCES_PRI_2_RENDERING_PRI_MAT);

    // Apply the ODT tone scale independently to RGB 
    float rgbPost[3];
    rgbPost[0] = odt_tonescale_fwd( rgbPre[0]);
    rgbPost[1] = odt_tonescale_fwd( rgbPre[1]);
    rgbPost[2] = odt_tonescale_fwd( rgbPre[2]);

  // Restore the hue to the pre-tonescale value
  float rgbRestored[3] = restore_hue_dw3( rgbPre, rgbPost);

  // Roll off highlights to avoid need for as much darkening.
  const float new_wht = 0.918;
  const float roll_width = 0.5;
  rgbRestored[0] = roll_white_fwd( rgbRestored[0] / ODT_OCES_WP, 
                                   new_wht, roll_width) * ODT_OCES_WP;
  rgbRestored[1] = roll_white_fwd( rgbRestored[1] / ODT_OCES_WP, 
                                   new_wht, roll_width) * ODT_OCES_WP;
  rgbRestored[2] = roll_white_fwd( rgbRestored[2] / ODT_OCES_WP, 
                                   new_wht, roll_width) * ODT_OCES_WP;

  // Clamp white to avoid casted highlights.
  const float scale = 0.96;
  rgbRestored[0] = min(rgbRestored[0], ODT_OCES_WP * new_wht) * scale;
  rgbRestored[1] = min(rgbRestored[1], ODT_OCES_WP * new_wht) * scale;
  rgbRestored[2] = min(rgbRestored[2], ODT_OCES_WP * new_wht) * scale;

  // Apply Black Point Compensation
  float offset_scaled[3];
  offset_scaled[0] = (SCALE * rgbRestored[0]) + BPC;
  offset_scaled[1] = (SCALE * rgbRestored[1]) + BPC;
  offset_scaled[2] = (SCALE * rgbRestored[2]) + BPC;    

  // Luminance to code value conversion. Scales the luminance white point, 
  // OUT_WP, to be CV 1.0 and OUT_BP to CV 0.0.
  float linearCV[3];
  linearCV[0] = (offset_scaled[0] - OUT_BP) / (OUT_WP - OUT_BP);
  linearCV[1] = (offset_scaled[1] - OUT_BP) / (OUT_WP - OUT_BP);
  linearCV[2] = (offset_scaled[2] - OUT_BP) / (OUT_WP - OUT_BP);

  // Convert rendering primaries RGB to CIE XYZ
  float XYZ[3] = mult_f3_f44( linearCV, RENDERING_PRI_2_XYZ_MAT);

  // CIE XYZ to display primaries
  float rgbOut[3] = mult_f3_f44( XYZ, XYZ_2_DISPLAY_PRI_MAT);

  // Clip negative values (i.e. projecting outside the display primaries)
  float rgbOutClamp[3] = clamp_f3( rgbOut, 0., HALF_POS_INF);
  
  // Restore hue after clip operation ("smart-clip")
  rgbOut = restore_hue_dw3( rgbOut, rgbOutClamp);

  // Encoding function
  float cctf[3];
  cctf[0] = CV_WHITE * pow( rgbOut[0], 1./DISPGAMMA);
  cctf[1] = CV_WHITE * pow( rgbOut[1], 1./DISPGAMMA);
  cctf[2] = CV_WHITE * pow( rgbOut[2], 1./DISPGAMMA);

  float outputCV[3] = clamp_f3( cctf, MIN_CV, MAX_CV);
  
  /*--- Cast outputCV to rOut, gOut, bOut ---*/
  // **NOTE**: The scaling step below is required when using ctlrender to 
  // process the images. When ctlrender sees a floating-point file as the input 
  // and an integral file format as the output, it assumes that values out the 
  // end of the transform will be floating point, and so multiplies the output 
  // values by (2^outputBitDepth)-1. Therefore, although the values of outputCV 
  // are the correct integer values, they must be scaled into a 0-1 range on 
  // output because ctlrender will scale them back up in the process of writing 
  // the integer file.
  // The ctlrender option -output_scale could be used for this, but currently 
  // this option does not appear to function correctly.
  rOut = outputCV[0] / (pow(2,BITDEPTH)-1);
  gOut = outputCV[1] / (pow(2,BITDEPTH)-1);
  bOut = outputCV[2] / (pow(2,BITDEPTH)-1);
  aOut = aIn;
}