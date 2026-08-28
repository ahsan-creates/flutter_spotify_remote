import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    override func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        super.scene(scene, openURLContexts: URLContexts)
        for context in URLContexts {
            UIApplication.shared.delegate?.application?(
                UIApplication.shared,
                open: context.url,
                options: [:]
            )
        }
    }
}
