import ARKit

class ViewController: UIViewController {

  // MARK: - Outlets
  @IBOutlet var sceneView: ARSCNView!
  @IBOutlet weak var unDoButton: UIButton!

  // MARK: - Properties
  /// Visualize planes
  var arePlanesHidden = false {
    didSet{
      planeNodes.forEach { $0.isHidden = arePlanesHidden }
    }
  }

  /// Adding node at user's point of tap.
  /// - Parameters:
  ///   - node: node, that must be added
  ///   - point: point of user's touch
  private func addNode(_ node: SCNNode, at point: CGPoint){
    guard let hitResult = sceneView.hitTest(point, types: .existingPlaneUsingExtent).first else { return }
    guard let anchor = hitResult.anchor as? ARPlaneAnchor, anchor.alignment == .horizontal else { return }
    node.simdTransform = hitResult.worldTransform
    addNodeToSceneRoot(node)
  }

  private func addNode(_ node: SCNNode, to parentNode: SCNNode){
    // Check that objects are not too close
    if let lastNode = lastNode {
      let lastPosition = lastNode.position
      let newPosition = node.position

      let x = lastPosition.x - newPosition.x
      let y = lastPosition.y - newPosition.y
      let z = lastPosition.z - newPosition.z

      let distanceSquare = x * x + y * y + z * z

      let minimumDistanceSquare = (lastNode.boundingBox.max.x * lastNode.boundingBox.max.x) + (lastNode.boundingBox.max.y * lastNode.boundingBox.max.y) + (lastNode.boundingBox.max.z * lastNode.boundingBox.max.z)
      print(minimumDistanceSquare)

      guard minimumDistanceSquare < distanceSquare else { return }
    }

    // Clone node to separate copies of object
    let clonedNode = node.clone()

    // Remember last placed node
    lastNode = clonedNode

    // Remember object plased for undo
    objectsPlased.append(clonedNode)

    // Add cloned node to scene
    parentNode.addChildNode(clonedNode)
  }

  private func addToParent(_ node: SCNNode){
    // Get poin of user's view position
    guard let pointOfView = sceneView.pointOfView else { return }
    let transform = pointOfView.transform

    // Take position and orientation in vector
    let orientation = SCNVector3(-transform.m31, -transform.m32, -transform.m33)
    let position = SCNVector3(transform.m41, transform.m42, transform.m43)

    // Translate position to selected none
    let currentPosition = plus(left: orientation, right: position)
    selectedNode?.position = currentPosition

    // Clone node to separate copies of object
    let clonedNode = node.clone()

    // Remember last placed node
    lastNode = clonedNode

    // Remember object plased for undo
    objectsPlased.append(clonedNode)

    // Add cloned node to scene
    sceneView.scene.rootNode.addChildNode(clonedNode)
  }

  private let configuration = ARWorldTrackingConfiguration()

  // Last node, placed by user
  private var lastNode: SCNNode?

  /// The node for an object currently selected by user
  private var selectedNode: SCNNode?

  enum ObjectPlacementMode {
    case freeform, plane, image, point
  }

  var objectMode: ObjectPlacementMode = .freeform

  /// Array of  and object plased
  var objectsPlased = [SCNNode]()

  /// Array of planes found
  var planeNodes = [SCNNode]()


  // MARK: - Methods
  /// Add node in front of camera
  private func addNodeInFront (_ node: SCNNode){
    // Get current camera's frame
    guard let frame = sceneView.session.currentFrame else { return }

    // Get transform property of camera
    let transform = frame.camera.transform
    var translation = matrix_identity_float4x4

    // Translate to 20 cm on z-axis
    translation.columns.3.z = -0.2

    // Rotate by .pi/2 on z-axis
    translation.columns.0.x = 0
    translation.columns.1.x = -1
    translation.columns.0.y = 1
    translation.columns.1.y = 0

    // Assign transform to the node
    node.simdTransform = matrix_multiply(transform, translation)

    // Add node to the scene
    addNodeToSceneRoot(node)

  }

  private func addNodeToImage(_ node: SCNNode, at point: CGPoint) {
    guard let result = sceneView.hitTest(point, options: [:]).first else { return }
    guard result.node.name == "image" else { return }
    node.transform = result.node.worldTransform
    node.eulerAngles.x = 0
    addNodeToSceneRoot(node)
  }

  private func addNodeToSceneRoot(_ node: SCNNode){
    addNode(node, to: sceneView.scene.rootNode)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    process(touches)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    process(touches)
  }

  private func plus (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    // placing objects at the same distance from the user to SCNVector3
    return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
  }

  private func process(_ touches: Set<UITouch>) {
    guard let touch = touches.first, let selectedNode = selectedNode else { return }
    let point = touch.location(in: sceneView)

    switch objectMode {
    case  .freeform:
      addNodeInFront(selectedNode)
    case .image:
      addNodeToImage(selectedNode, at: point)
    case  .plane:
      addNode(selectedNode, at: point)
    case .point:
      addToParent(selectedNode)
    }
  }


  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "showOptions" {
      let optionsViewController = segue.destination as! OptionsContainerViewController
      optionsViewController.delegate = self
    }
  }

  private func reloadConfiguration(reset: Bool = false) {
    // Clear objects placed
    objectsPlased.forEach { $0.removeFromParentNode() }
    objectsPlased.removeAll()

    // Clear planes placed
    planeNodes.forEach { $0.removeFromParentNode() }
    planeNodes.removeAll()

    //Hide all future planes
    arePlanesHidden = true

    // Remove existing anchors if reset is true
    let options: ARSession.RunOptions = reset ? .removeExistingAnchors : []

    // Reload configuration
    configuration.detectionImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)
    configuration.planeDetection = .horizontal
    sceneView.session.run(configuration, options: options)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sceneView.delegate = self
    sceneView.autoenablesDefaultLighting = true

  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadConfiguration()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sceneView.session.pause()
  }

  // MARK: - Actions
  @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
      objectMode = .freeform
      arePlanesHidden = true
    case 1:
      objectMode = .plane
      arePlanesHidden = false
    case 2:
      objectMode = .image
      arePlanesHidden = true
    case 3:
      objectMode = .point
      arePlanesHidden = true
    default:
      break
    }
  }

}

// MARK: - OptionsViewControllerDelegate
extension ViewController: OptionsViewControllerDelegate {

  func objectSelected(node: SCNNode) {
    dismiss(animated: true, completion: nil)
    selectedNode = node
  }

  func togglePlaneVisualization() {
    dismiss(animated: true)
    guard objectMode == .plane else { return }
    arePlanesHidden.toggle()
  }

  func undoLastObject() {
    if let lastObject = objectsPlased.last {
      lastObject.removeFromParentNode()
      objectsPlased.removeLast()
    } else {
      dismiss(animated: true)
    }
  }

  func resetScene() {
    reloadConfiguration(reset: true)
    dismiss(animated: true)
  }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate{

  private func createFloor(with size: CGSize, opacity: CGFloat = 0.25) -> SCNNode{
    // Get estimated plane size
    let  plane = SCNPlane(width: size.width, height: size.height)
    plane.firstMaterial?.diffuse.contents = UIColor.green
    let planeNode = SCNNode(geometry: plane)
    planeNode.eulerAngles.x -= .pi/2
    planeNode.opacity = opacity
    return planeNode
  }

  private func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor){
    // Put plane at the image
    let size = anchor.referenceImage.physicalSize
    let coverNode = createFloor(with: size, opacity: 0.1)
    coverNode.name = "image"
    node.addChildNode(coverNode)
  }

  private func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor){
    let extent = anchor.extent
    let size = CGSize(width: CGFloat(extent.x), height: CGFloat(extent.z))
    let planeNode = createFloor(with: size)
    planeNode.isHidden = arePlanesHidden
    // Add plane node to list of plane nodes
    planeNodes.append(planeNode)
    node.addChildNode(planeNode)
  }

  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    switch anchor {
    case let imageAnchor as ARImageAnchor:
      nodeAdded(node, for: imageAnchor)
    case let planeAnchor as ARPlaneAnchor:
      nodeAdded(node, for: planeAnchor)
    default:
      print(#line, #function, "Unknown anchor found!")
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    switch anchor{
    case is ARImageAnchor:
      break
    case let planeAnchor as ARPlaneAnchor:
      updateFloor(for: node, anchor: planeAnchor)
    default:
      print("Unknown type of \(anchor) found!")
    }
  }

  private func updateFloor(for node: SCNNode, anchor: ARPlaneAnchor) {
    guard let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane else { return }
    // Get estimated plane size
    let extent = anchor.extent
    plane.width = CGFloat(extent.x)
    plane.height = CGFloat(extent.z)
    // Positioning node in the center
    planeNode.simdPosition = anchor.center

  }
}
