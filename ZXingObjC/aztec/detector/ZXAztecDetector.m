#import "ZXAztecDetector.h"
#import "ZXAztecDetectorResult.h"
#import "ZXGenericGF.h"
#import "ZXGridSampler.h"
#import "ZXNotFoundException.h"
#import "ZXReedSolomonDecoder.h"
#import "ZXReedSolomonException.h"
#import "ZXResultPoint.h"
#import "ZXWhiteRectangleDetector.h"

@interface ZXAztecPoint : NSObject

@property (nonatomic, assign) int x;
@property (nonatomic, assign) int y;

- (id)initWithX:(int) x y:(int)y;
- (ZXResultPoint *)toResultPoint;

@end

@implementation ZXAztecPoint

@synthesize x, y;

- (id)initWithX:(int)anX y:(int)aY {
  if (self = [super init]) {
    x = anX;
    y = aY;
  }
  return self;
}

- (ZXResultPoint *)toResultPoint {
  return [[[ZXResultPoint alloc] initWithX:x y:y] autorelease];
}

@end

@interface ZXAztecDetector ()

@property (nonatomic, assign) BOOL compact;
@property (nonatomic, retain) ZXBitMatrix* image;
@property (nonatomic, assign) int nbCenterLayers;
@property (nonatomic, assign) int nbDataBlocks;
@property (nonatomic, assign) int nbLayers;
@property (nonatomic, assign) int shift;

- (NSArray *)bullEyeCornerPoints:(ZXAztecPoint *)pCenter;
- (int)color:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2;
- (void)correctParameterData:(NSMutableArray *)parameterData compact:(BOOL)compact;
- (float)distance:(ZXAztecPoint *)a b:(ZXAztecPoint *)b;
- (void)extractParameters:(NSArray *)bullEyeCornerPoints;
- (ZXAztecPoint *)firstDifferent:(ZXAztecPoint *)init color:(BOOL)color dx:(int)dx dy:(int)dy;
- (BOOL)isValidX:(int)x y:(int)y;
- (BOOL)isWhiteOrBlackRectangle:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2 p3:(ZXAztecPoint *)p3 p4:(ZXAztecPoint *)p4;
- (ZXAztecPoint *)matrixCenter;
- (NSArray *)matrixCornerPoints:(NSArray *)bullEyeCornerPoints;
- (void)parameters:(NSMutableArray *)parameterData;
- (int)round:(float)d;
- (ZXBitMatrix *)sampleGrid:(ZXBitMatrix *)image
                    topLeft:(ZXResultPoint *)topLeft
                 bottomLeft:(ZXResultPoint *)bottomLeft
                bottomRight:(ZXResultPoint *)bottomRight
                   topRight:(ZXResultPoint *)topRight;
- (NSArray *)sampleLine:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2 size:(int)size;

@end

@implementation ZXAztecDetector

@synthesize compact;
@synthesize image;
@synthesize nbCenterLayers;
@synthesize nbDataBlocks;
@synthesize nbLayers;
@synthesize shift;

- (id)initWithImage:(ZXBitMatrix*)anImage {
  if (self = [super init]) {
    self.image = anImage;
  }
  return self;
}

- (void) dealloc {
  [image release];

  [super dealloc];
}

/**
 * Detects an Aztec Code in an image.
 */
- (ZXAztecDetectorResult *)detect {
  // 1. Get the center of the aztec matrix
  ZXAztecPoint* pCenter = [self matrixCenter];

  // 2. Get the corners of the center bull's eye
  NSArray * bullEyeCornerPoints = [self bullEyeCornerPoints:pCenter];

  // 3. Get the size of the matrix from the bull's eye
  [self extractParameters:bullEyeCornerPoints];

  // 4. Get the corners of the matrix
  NSArray * corners = [self matrixCornerPoints:bullEyeCornerPoints];

  // 5. Sample the grid
  ZXBitMatrix *bits = [self sampleGrid:self.image
                               topLeft:[corners objectAtIndex:self.shift % 4]
                            bottomLeft:[corners objectAtIndex:(self.shift + 3) % 4]
                           bottomRight:[corners objectAtIndex:(self.shift + 2) % 4]
                              topRight:[corners objectAtIndex:(self.shift + 1) % 4]];

  return [[[ZXAztecDetectorResult alloc] initWithBits:bits
                                               points:corners
                                              compact:self.compact
                                         nbDatablocks:self.nbDataBlocks
                                             nbLayers:self.nbLayers] autorelease];
}


/**
 * Extracts the number of data layers and data blocks from the layer around the bull's eye
 */
- (void)extractParameters:(NSArray*)bullEyeCornerPoints {
  ZXAztecPoint *p0 = [bullEyeCornerPoints objectAtIndex:0];
  ZXAztecPoint *p1 = [bullEyeCornerPoints objectAtIndex:1];
  ZXAztecPoint *p2 = [bullEyeCornerPoints objectAtIndex:2];
  ZXAztecPoint *p3 = [bullEyeCornerPoints objectAtIndex:3];

  NSArray *resab = [self sampleLine:p0 p2:p1 size:2 * self.nbCenterLayers + 1];
  NSArray *resbc = [self sampleLine:p1 p2:p2 size:2 * self.nbCenterLayers + 1];
  NSArray *rescd = [self sampleLine:p2 p2:p3 size:2 * self.nbCenterLayers + 1];
  NSArray *resda = [self sampleLine:p3 p2:p0 size:2 * self.nbCenterLayers + 1];

  if ([[resab objectAtIndex:0] boolValue] && [[resab objectAtIndex:2 * self.nbCenterLayers] boolValue]) {
    self.shift = 0;
  } else if ([[resbc objectAtIndex:0] boolValue] && [[resbc objectAtIndex:2 * self.nbCenterLayers] boolValue]) {
    self.shift = 1;
  } else if ([[rescd objectAtIndex:0] boolValue] && [[rescd objectAtIndex:2 * self.nbCenterLayers] boolValue]) {
    self.shift = 2;
  } else if ([[resda objectAtIndex:0] boolValue] && [[resda objectAtIndex:2 * self.nbCenterLayers] boolValue]) {
    self.shift = 3;
  } else {
    @throw [ZXNotFoundException notFoundInstance];
  }

  NSMutableArray *parameterData = [NSMutableArray array];
  NSMutableArray *shiftedParameterData = [NSMutableArray array];
  if (self.compact) {
    for (int i = 0; i < 28; i++) {
      [shiftedParameterData addObject:[NSNumber numberWithBool:NO]];
    }

    for (int i = 0; i < 7; i++) {
      [shiftedParameterData replaceObjectAtIndex:i withObject:[resab objectAtIndex:2+i]];
      [shiftedParameterData replaceObjectAtIndex:i + 7 withObject:[resbc objectAtIndex:2+i]];
      [shiftedParameterData replaceObjectAtIndex:i + 14 withObject:[rescd objectAtIndex:2+i]];
      [shiftedParameterData replaceObjectAtIndex:i + 21 withObject:[resda objectAtIndex:2+i]];
    }

    for (int i = 0; i < 28; i++) {
      [parameterData addObject:[shiftedParameterData objectAtIndex:(i + shift * 7) % 28]];
    }
  } else {
    for (int i = 0; i < 40; i++) {
      [shiftedParameterData addObject:[NSNumber numberWithBool:NO]];
    }

    for (int i = 0; i < 11; i++) {
      if (i < 5) {
        [shiftedParameterData replaceObjectAtIndex:i withObject:[resab objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 10 withObject:[resbc objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 20 withObject:[rescd objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 30 withObject:[resda objectAtIndex:2 + i]];
      }
      if (i > 5) {
        [shiftedParameterData replaceObjectAtIndex:i - 1 withObject:[resab objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 10 - 1 withObject:[resbc objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 20 - 1 withObject:[rescd objectAtIndex:2 + i]];
        [shiftedParameterData replaceObjectAtIndex:i + 30 - 1 withObject:[resda objectAtIndex:2 + i]];
      }
    }

    for (int i = 0; i < 40; i++) {
      [parameterData addObject:[shiftedParameterData objectAtIndex:(i + shift * 10) % 40]];
    }
  }

  [self correctParameterData:parameterData compact:self.compact];
  [self parameters:parameterData];
}


/**
 * 
 * Gets the Aztec code corners from the bull's eye corners and the parameters
 */
- (NSArray *)matrixCornerPoints:(NSArray *)bullEyeCornerPoints {
  ZXAztecPoint *p0 = [bullEyeCornerPoints objectAtIndex:0];
  ZXAztecPoint *p1 = [bullEyeCornerPoints objectAtIndex:1];
  ZXAztecPoint *p2 = [bullEyeCornerPoints objectAtIndex:2];
  ZXAztecPoint *p3 = [bullEyeCornerPoints objectAtIndex:3];

  float ratio = (2 * self.nbLayers + (self.nbLayers > 4 ? 1 : 0) + (self.nbLayers - 4) / 8) / (2.0f * self.nbCenterLayers);

  int dx = p0.x - p2.x;
  dx += dx > 0 ? 1 : -1;
  int dy = p0.y - p2.y;
  dy += dy > 0 ? 1 : -1;

  int targetcx = [self round:p2.x - ratio * dx];
  int targetcy = [self round:p2.y - ratio * dy];

  int targetax = [self round:p0.x + ratio * dx];
  int targetay = [self round:p0.y + ratio * dy];

  dx = p1.x - p3.x;
  dx += dx > 0 ? 1 : -1;
  dy = p1.y - p3.y;
  dy += dy > 0 ? 1 : -1;

  int targetdx = [self round:p3.x - ratio * dx];
  int targetdy = [self round:p3.y - ratio * dy];
  int targetbx = [self round:p1.x + ratio * dx];
  int targetby = [self round:p1.y + ratio * dy];

  if (![self isValidX:targetax y:targetay] ||
      ![self isValidX:targetbx y:targetby] ||
      ![self isValidX:targetcx y:targetcy] ||
      ![self isValidX:targetdx y:targetdy]) {
    @throw [ZXNotFoundException notFoundInstance];
  }

  return [NSArray arrayWithObjects:
          [[[ZXResultPoint alloc] initWithX:targetax y:targetay] autorelease],
          [[[ZXResultPoint alloc] initWithX:targetbx y:targetby] autorelease],
          [[[ZXResultPoint alloc] initWithX:targetcx y:targetcy] autorelease],
          [[[ZXResultPoint alloc] initWithX:targetdx y:targetdy] autorelease], nil];
}


/**
 * 
 * Corrects the parameter bits using Reed-Solomon algorithm
 */
- (void)correctParameterData:(NSMutableArray *)parameterData compact:(BOOL)isCompact {
  int numCodewords;
  int numDataCodewords;

  if (isCompact) {
    numCodewords = 7;
    numDataCodewords = 2;
  } else {
    numCodewords = 10;
    numDataCodewords = 4;
  }

  int numECCodewords = numCodewords - numDataCodewords;
  int parameterWordsLen = numCodewords;
  int parameterWords[parameterWordsLen];

  int codewordSize = 4;
  for (int i = 0; i < parameterWordsLen; i++) {
    parameterWords[i] = 0;
    int flag = 1;
    for (int j = 1; j <= codewordSize; j++) {
      if ([[parameterData objectAtIndex:codewordSize * i + codewordSize - j] boolValue]) {
        parameterWords[i] += flag;
      }
      flag <<= 1;
    }
  }

  @try {
    ZXReedSolomonDecoder *rsDecoder = [[[ZXReedSolomonDecoder alloc] initWithField:[ZXGenericGF AztecDataParam]] autorelease];
    [rsDecoder decode:parameterWords receivedLen:parameterWordsLen twoS:numECCodewords];
  } @catch (ZXReedSolomonException * rse) {
    @throw [ZXNotFoundException notFoundInstance];
  }

  for (int i = 0; i < numDataCodewords; i++) {
    int flag = 1;
    for (int j = 1; j <= codewordSize; j++) {
      [parameterData replaceObjectAtIndex:i * codewordSize + codewordSize - j
                               withObject:[NSNumber numberWithBool:(parameterWords[i] & flag) == flag]];
      flag <<= 1;
    }
  }
}


/**
 * 
 * Finds the corners of a bull-eye centered on the passed point
 */
- (NSArray *)bullEyeCornerPoints:(ZXAztecPoint *)pCenter {
  ZXAztecPoint *pina = pCenter;
  ZXAztecPoint *pinb = pCenter;
  ZXAztecPoint *pinc = pCenter;
  ZXAztecPoint *pind = pCenter;

  BOOL color = YES;

  for (self.nbCenterLayers = 1; self.nbCenterLayers < 9; self.nbCenterLayers++) {
    ZXAztecPoint *pouta = [self firstDifferent:pina color:color dx:1 dy:-1];
    ZXAztecPoint *poutb = [self firstDifferent:pinb color:color dx:1 dy:1];
    ZXAztecPoint *poutc = [self firstDifferent:pinc color:color dx:-1 dy:1];
    ZXAztecPoint *poutd = [self firstDifferent:pind color:color dx:-1 dy:-1];

    if (self.nbCenterLayers > 2) {
      float q = [self distance:poutd b:pouta] * self.nbCenterLayers / ([self distance:pind b:pina] * (self.nbCenterLayers + 2));
      if (q < 0.75 || q > 1.25 || ![self isWhiteOrBlackRectangle:pouta p2:poutb p3:poutc p4:poutd]) {
        break;
      }
    }

    pina = pouta;
    pinb = poutb;
    pinc = poutc;
    pind = poutd;

    color = !color;
  }

  if (nbCenterLayers != 5 && nbCenterLayers != 7) {
    @throw [ZXNotFoundException notFoundInstance];
  }

  self.compact = self.nbCenterLayers == 5;

  float ratio = 0.75f * 2 / (2 * nbCenterLayers - 3);

  int dx = pina.x - pinc.x;
  int dy = pina.y - pinc.y;
  int targetcx = [self round:pinc.x - ratio * dx];
  int targetcy = [self round:pinc.y - ratio * dy];
  int targetax = [self round:pina.x + ratio * dx];
  int targetay = [self round:pina.y + ratio * dy];

  dx = pinb.x - pind.x;
  dy = pinb.y - pind.y;

  int targetdx = [self round:pind.x - ratio * dx];
  int targetdy = [self round:pind.y - ratio * dy];
  int targetbx = [self round:pinb.x + ratio * dx];
  int targetby = [self round:pinb.y + ratio * dy];

  if (![self isValidX:targetax y:targetay] ||
      ![self isValidX:targetbx y:targetby] ||
      ![self isValidX:targetcx y:targetcy] ||
      ![self isValidX:targetdx y:targetdy]) {
    @throw [ZXNotFoundException notFoundInstance];
  }

  ZXAztecPoint * pa = [[[ZXAztecPoint alloc] initWithX:targetax y:targetay] autorelease];
  ZXAztecPoint * pb = [[[ZXAztecPoint alloc] initWithX:targetbx y:targetby] autorelease];
  ZXAztecPoint * pc = [[[ZXAztecPoint alloc] initWithX:targetcx y:targetcy] autorelease];
  ZXAztecPoint * pd = [[[ZXAztecPoint alloc] initWithX:targetdx y:targetdy] autorelease];

  return [NSArray arrayWithObjects:pa, pb, pc, pd, nil];
}


/**
 * 
 * Finds a candidate center point of an Aztec code from an image
 */
- (ZXAztecPoint *)matrixCenter {
  ZXResultPoint *pointA;
  ZXResultPoint *pointB;
  ZXResultPoint *pointC;
  ZXResultPoint *pointD;

  @try {
    NSArray * cornerPoints = [[[[ZXWhiteRectangleDetector alloc] initWithImage:self.image] autorelease] detect];
    pointA = [cornerPoints objectAtIndex:0];
    pointB = [cornerPoints objectAtIndex:1];
    pointC = [cornerPoints objectAtIndex:2];
    pointD = [cornerPoints objectAtIndex:3];
  } @catch (ZXNotFoundException * e) {
    int cx = self.image.width / 2;
    int cy = self.image.height / 2;
    pointA = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx + 15 / 2 y:cy - 15 / 2] autorelease] color:NO dx:1 dy:-1] toResultPoint];
    pointB = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx + 15 / 2 y:cy + 15 / 2] autorelease] color:NO dx:1 dy:1] toResultPoint];
    pointC = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx - 15 / 2 y:cy + 15 / 2] autorelease] color:NO dx:-1 dy:1] toResultPoint];
    pointD = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx - 15 / 2 y:cy - 15 / 2] autorelease] color:NO dx:-1 dy:-1] toResultPoint];
  }

  int cx = [self round:([pointA x] + [pointD x] + [pointB x] + [pointC x]) / 4];
  int cy = [self round:([pointA y] + [pointD y] + [pointB y] + [pointC y]) / 4];

  @try {
    NSArray * cornerPoints = [[[[ZXWhiteRectangleDetector alloc] initWithImage:self.image initSize:15 x:cx y:cy] autorelease] detect];
    pointA = [cornerPoints objectAtIndex:0];
    pointB = [cornerPoints objectAtIndex:1];
    pointC = [cornerPoints objectAtIndex:2];
    pointD = [cornerPoints objectAtIndex:3];
  } @catch (ZXNotFoundException * e) {
    pointA = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx + 15 / 2 y:cy - 15 / 2] autorelease] color:NO dx:1 dy:-1] toResultPoint];
    pointB = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx + 15 / 2 y:cy + 15 / 2] autorelease] color:NO dx:1 dy:1] toResultPoint];
    pointC = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx - 15 / 2 y:cy + 15 / 2] autorelease] color:NO dx:-1 dy:1] toResultPoint];
    pointD = [[self firstDifferent:[[[ZXAztecPoint alloc] initWithX:cx - 15 / 2 y:cy - 15 / 2] autorelease] color:NO dx:-1 dy:-1] toResultPoint];
  }

  cx = [self round:([pointA x] + [pointD x] + [pointB x] + [pointC x]) / 4];
  cy = [self round:([pointA y] + [pointD y] + [pointB y] + [pointC y]) / 4];

  return [[[ZXAztecPoint alloc] initWithX:cx y:cy] autorelease];
}


/**
 * Samples an Aztec matrix from an image
 */
- (ZXBitMatrix *)sampleGrid:(ZXBitMatrix *)anImage topLeft:(ZXResultPoint *)topLeft bottomLeft:(ZXResultPoint *)bottomLeft bottomRight:(ZXResultPoint *)bottomRight topRight:(ZXResultPoint *)topRight {
  int dimension;
  if (self.compact) {
    dimension = 4 * self.nbLayers + 11;
  } else {
    if (self.nbLayers <= 4) {
      dimension = 4 * self.nbLayers + 15;
    } else {
      dimension = 4 * self.nbLayers + 2 * ((self.nbLayers - 4) / 8 + 1) + 15;
    }
  }

  ZXGridSampler * sampler = [ZXGridSampler instance];

  return [sampler sampleGrid:anImage
                  dimensionX:dimension
                  dimensionY:dimension
                       p1ToX:0.5f
                       p1ToY:0.5f
                       p2ToX:dimension - 0.5f
                       p2ToY:0.5f
                       p3ToX:dimension - 0.5f
                       p3ToY:dimension - 0.5f
                       p4ToX:0.5f
                       p4ToY:dimension - 0.5f
                     p1FromX:topLeft.x
                     p1FromY:topLeft.y
                     p2FromX:topRight.x
                     p2FromY:topRight.y
                     p3FromX:bottomRight.x
                     p3FromY:bottomRight.y
                     p4FromX:bottomLeft.x
                     p4FromY:bottomLeft.y];
}


/**
 * Sets number of layers and number of datablocks from parameter bits
 */
- (void)parameters:(NSArray *)parameterData {
  int nbBitsForNbLayers;
  int nbBitsForNbDatablocks;

  if (self.compact) {
    nbBitsForNbLayers = 2;
    nbBitsForNbDatablocks = 6;
  } else {
    nbBitsForNbLayers = 5;
    nbBitsForNbDatablocks = 11;
  }

  for (int i = 0; i < nbBitsForNbLayers; i++) {
    self.nbLayers <<= 1;
    if ([[parameterData objectAtIndex:i] boolValue]) {
      self.nbLayers += 1;
    }
  }

  for (int i = nbBitsForNbLayers; i < nbBitsForNbLayers + nbBitsForNbDatablocks; i++) {
    self.nbDataBlocks <<= 1;
    if ([[parameterData objectAtIndex:i] boolValue]) {
      self.nbDataBlocks += 1;
    }
  }

  self.nbLayers++;
  self.nbDataBlocks++;
}


/**
 * 
 * Samples a line
 */
- (NSArray *)sampleLine:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2 size:(int)size {
  NSMutableArray * res = [NSMutableArray arrayWithCapacity:size];
  float d = [self distance:p1 b:p2];
  float moduleSize = d / (size - 1);
  float dx = moduleSize * (p2.x - p1.x) / d;
  float dy = moduleSize * (p2.y - p1.y) / d;

  float px = p1.x;
  float py = p1.y;

  for (int i = 0; i < size; i++) {
    [res addObject:[NSNumber numberWithBool:[self.image getX:[self round:px] y:[self round:py]]]];
    px += dx;
    py += dy;
  }

  return res;
}


/**
 * return true if the border of the rectangle passed in parameter is compound of white points only
 * or black points only
 */
- (BOOL)isWhiteOrBlackRectangle:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2 p3:(ZXAztecPoint *)p3 p4:(ZXAztecPoint *)p4 {
  int corr = 3;

  p1 = [[[ZXAztecPoint alloc] initWithX:p1.x - corr y:p1.y + corr] autorelease];
  p2 = [[[ZXAztecPoint alloc] initWithX:p2.x - corr y:p2.y - corr] autorelease];
  p3 = [[[ZXAztecPoint alloc] initWithX:p3.x + corr y:p3.y - corr] autorelease];
  p4 = [[[ZXAztecPoint alloc] initWithX:p4.x + corr y:p4.y + corr] autorelease];

  int cInit = [self color:p4 p2:p1];
  if (cInit == 0) {
    return NO;
  }

  int c = [self color:p1 p2:p2];
  if (c != cInit || c == 0) {
    return NO;
  }

  c = [self color:p2 p2:p3];
  if (c != cInit || c == 0) {
    return NO;
  }

  c = [self color:p3 p2:p4];
  return c == cInit && c != 0;
}


/**
 * Gets the color of a segment
 * return 1 if segment more than 90% black, -1 if segment is more than 90% white, 0 else
 */
- (int)color:(ZXAztecPoint *)p1 p2:(ZXAztecPoint *)p2 {
  float d = [self distance:p1 b:p2];
  float dx = (p2.x - p1.x) / d;
  float dy = (p2.y - p1.y) / d;
  int error = 0;

  float px = p1.x;
  float py = p1.y;

  BOOL colorModel = [self.image getX:p1.x y:p1.y];

  for (int i = 0; i < d; i++) {
    px += dx;
    py += dy;
    if ([self.image getX:[self round:px] y:[self round:py]] != colorModel) {
      error++;
    }
  }

  float errRatio = (float)error / d;

  if (errRatio > 0.1 && errRatio < 0.9) {
    return 0;
  }

  if (errRatio <= 0.1) {
    return colorModel ? 1 : -1;
  } else {
    return colorModel ? -1 : 1;
  }
}


/**
 * Gets the coordinate of the first point with a different color in the given direction
 */
- (ZXAztecPoint *)firstDifferent:(ZXAztecPoint *)init color:(BOOL)color dx:(int)dx dy:(int)dy {
  int x = init.x + dx;
  int y = init.y + dy;

  while ([self isValidX:x y:y] && [self.image getX:x y:y] == color) {
    x += dx;
    y += dy;
  }

  x -= dx;
  y -= dy;

  while ([self isValidX:x y:y] && [self.image getX:x y:y] == color) {
    x += dx;
  }
  x -= dx;

  while ([self isValidX:x y:y] && [self.image getX:x y:y] == color) {
    y += dy;
  }
  y -= dy;

  return [[[ZXAztecPoint alloc] initWithX:x y:y] autorelease];
}

- (BOOL) isValidX:(int)x y:(int)y {
  return x >= 0 && x < self.image.width && y > 0 && y < self.image.height;
}


/**
 * Ends up being a bit faster than round(). This merely rounds its
 * argument to the nearest int, where x.5 rounds up.
 */
- (int)round:(float)d {
  return (int)(d + 0.5f);
}

- (float)distance:(ZXAztecPoint *)a b:(ZXAztecPoint *)b {
  return (float)sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

@end
