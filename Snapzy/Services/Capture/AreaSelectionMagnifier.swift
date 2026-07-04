import Cocoa
import QuartzCore

final class AreaSelectionMagnifier {
  // Configurable bounds/sizes
  private let magnifierSize: CGFloat = 130.0
  private let magnifierGap: CGFloat = 20.0
  private let minMagnifierZoom: CGFloat = 1.0
  private let maxMagnifierZoom: CGFloat = 20.0

  // The layers managed by this magnifier
  private(set) var containerLayer: CALayer?
  private(set) var imageLayer: CALayer?
  private(set) var centerPixelLayer: CAShapeLayer?
  private(set) var infoBackgroundLayer: CALayer?
  private(set) var infoTextLayer: CATextLayer?

  var zoom: CGFloat = 1.0 // Starts at 1.0 (deactivated)
  var reverseZoomDirection = false

  // Disables default layer animations
  private let disabledActions: [String: CAAction] = [
    kCAOnOrderIn: NSNull(),
    kCAOnOrderOut: NSNull(),
    "sublayers": NSNull(),
    "contents": NSNull(),
    "bounds": NSNull(),
    "position": NSNull(),
    "hidden": NSNull(),
    "contentsRect": NSNull()
  ]

  private var overlayFont: NSFont {
    NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
  }

  private var overlayTextAttributes: [NSAttributedString.Key: Any] {
    [
      .font: overlayFont,
      .foregroundColor: NSColor.white,
    ]
  }

  func setupLayersIfNeeded(in rootLayer: CALayer, contentsScale: CGFloat) {
    guard containerLayer == nil else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Container layer: provides border, corner radius, and shadow
    let container = CALayer()
    container.frame = CGRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize)
    container.cornerRadius = 12
    container.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
    container.borderWidth = 1.5
    container.shadowColor = NSColor.black.cgColor
    container.shadowOffset = CGSize(width: 0, height: -4)
    container.shadowRadius = 8
    container.shadowOpacity = 0.4
    container.actions = disabledActions
    container.isHidden = true
    rootLayer.addSublayer(container)
    self.containerLayer = container

    // Image layer: displays nearest-neighbor pixelated zoom
    let imgLayer = CALayer()
    imgLayer.frame = container.bounds
    imgLayer.cornerRadius = 12
    imgLayer.masksToBounds = true
    imgLayer.magnificationFilter = .nearest
    imgLayer.contentsGravity = .resize
    imgLayer.actions = disabledActions
    container.addSublayer(imgLayer)
    self.imageLayer = imgLayer

    // Center pixel indicator layer: thin border highlighting the target pixel
    let centerIndicator = CAShapeLayer()
    centerIndicator.strokeColor = NSColor.systemRed.cgColor
    centerIndicator.fillColor = nil
    centerIndicator.lineWidth = 1.0
    centerIndicator.actions = disabledActions
    imgLayer.addSublayer(centerIndicator)
    self.centerPixelLayer = centerIndicator

    // Info Pill Background
    let infoBg = CALayer()
    infoBg.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
    infoBg.cornerRadius = 4
    infoBg.actions = disabledActions
    container.addSublayer(infoBg)
    self.infoBackgroundLayer = infoBg

    // Info Pill Text
    let infoText = CATextLayer()
    infoText.actions = disabledActions
    infoText.font = overlayFont as CTFont
    infoText.fontSize = overlayFont.pointSize
    infoText.foregroundColor = NSColor.white.cgColor
    infoText.alignmentMode = .left
    infoText.contentsScale = contentsScale
    infoText.truncationMode = .none
    infoText.isWrapped = false
    infoText.isHidden = true
    container.addSublayer(infoText)
    self.infoTextLayer = infoText

    CATransaction.commit()
  }

  func removeLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    containerLayer?.removeFromSuperlayer()
    containerLayer = nil
    imageLayer = nil
    centerPixelLayer = nil
    infoBackgroundLayer = nil
    infoTextLayer = nil
    CATransaction.commit()
  }

  func handleScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool) -> Bool {
    let multiplier: CGFloat = hasPreciseScrollingDeltas ? 0.2 : 1.0
    var directionSign: CGFloat = delta > 0 ? 1.0 : -1.0
    if reverseZoomDirection {
      directionSign = -directionSign
    }
    let zoomChange = directionSign * multiplier
    let oldZoom = zoom
    zoom = max(minMagnifierZoom, min(maxMagnifierZoom, zoom + zoomChange))
    return zoom != oldZoom
  }

  func update(
    at point: CGPoint,
    bounds: CGRect,
    backdropImage: CGImage?,
    pixelData: [UInt8]?,
    backdropWidth: Int,
    backdropHeight: Int,
    backdropScale: CGFloat,
    contentsScale: CGFloat,
    in rootLayer: CALayer
  ) {
    guard zoom > 1.0, let backdropImage = backdropImage else {
      removeLayers()
      return
    }

    setupLayersIfNeeded(in: rootLayer, contentsScale: contentsScale)

    guard let container = containerLayer,
          let imgLayer = imageLayer,
          let centerIndicator = centerPixelLayer,
          let infoBg = infoBackgroundLayer,
          let infoText = infoTextLayer else {
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Compute magnifier window frame based on mouse position
    var originX = point.x + magnifierGap
    var originY = point.y + magnifierGap

    // Check boundary & flip dynamically
    if originX + magnifierSize > bounds.maxX {
      originX = point.x - magnifierGap - magnifierSize
    }
    if originY + magnifierSize > bounds.maxY {
      originY = point.y - magnifierGap - magnifierSize
    }

    // Absolute screen clamping
    originX = max(bounds.minX, min(bounds.maxX - magnifierSize, originX))
    originY = max(bounds.minY, min(bounds.maxY - magnifierSize, originY))

    container.frame = CGRect(x: originX, y: originY, width: magnifierSize, height: magnifierSize)
    container.isHidden = false

    // Set cropped and scaled image contents via contentsRect (nearest-neighbor)
    imgLayer.contents = backdropImage
    let norm_w = magnifierSize / (zoom * bounds.width)
    let norm_h = magnifierSize / (zoom * bounds.height)
    let norm_x = (point.x / bounds.width) - norm_w / 2.0
    let norm_y = (point.y / bounds.height) - norm_h / 2.0
    imgLayer.contentsRect = CGRect(x: norm_x, y: norm_y, width: norm_w, height: norm_h)

    // Central pixel highlight rect
    let cx = magnifierSize / 2.0
    let cy = magnifierSize / 2.0
    let px = cx - zoom / 2.0
    let py = cy - zoom / 2.0
    let pixelRect = CGRect(x: px, y: py, width: zoom, height: zoom)
    centerIndicator.path = CGPath(rect: pixelRect, transform: nil)

    // Read pixel color under cursor from backdropPixelDataArray
    var hexText = ""
    if let pixelData = pixelData, backdropWidth > 0, backdropHeight > 0 {
      let scaleX = bounds.width > 0 ? CGFloat(backdropWidth) / bounds.width : backdropScale
      let scaleY = bounds.height > 0 ? CGFloat(backdropHeight) / bounds.height : backdropScale
      let pixelX = point.x * scaleX
      let pixelY = point.y * scaleY
      let x = max(0, min(backdropWidth - 1, Int(pixelX)))
      let y = max(0, min(backdropHeight - 1, backdropHeight - 1 - Int(pixelY)))
      let pixelOffset = (y * backdropWidth + x) * 4
      if pixelOffset + 2 < pixelData.count {
        let r = pixelData[pixelOffset]
        let g = pixelData[pixelOffset + 1]
        let b = pixelData[pixelOffset + 2]
        hexText = String(format: "#%02X%02X%02X", r, g, b)
      }
    }

    let zoomString = String(format: "%.0fx", zoom)
    let infoString = hexText.isEmpty ? zoomString : "\(zoomString) • \(hexText)"
    let attributes = overlayTextAttributes
    let textSize = infoString.size(withAttributes: attributes)
    let textPadding: CGFloat = 4.0
    let pillWidth = textSize.width + textPadding * 4
    let pillHeight = textSize.height + textPadding
    let pillX = (magnifierSize - pillWidth) / 2.0
    let pillY = 6.0

    infoBg.frame = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
    infoBg.isHidden = false

    infoText.string = infoString
    infoText.frame = CGRect(
      x: pillX + textPadding * 2,
      y: pillY + textPadding / 2.0 - 0.5,
      width: textSize.width,
      height: textSize.height
    )
    infoText.isHidden = false

    CATransaction.commit()
  }
}
