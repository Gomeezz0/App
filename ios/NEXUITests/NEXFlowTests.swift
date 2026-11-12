import CoreLocation
import XCTest

/// Recorre la app de principio a fin en el simulador, contra el backend real, y guarda una
/// captura de cada pantalla en /tmp/nex-shots (el CI las publica en docs/capturas).
final class NEXFlowTests: XCTestCase {
    private let app = XCUIApplication()
    private let shots = URL(fileURLWithPath: "/tmp/nex-shots")
    private var counter = 0

    // Puerta del Sol, Madrid. El CI siembra avisos alrededor de este punto.
    private let start = CLLocation(latitude: 40.4168, longitude: -3.7038)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        XCUIDevice.shared.location = XCUILocation(location: start)
    }

    private func shot(_ name: String) {
        counter += 1
        let screenshot = XCUIScreen.main.screenshot()
        let file = shots.appendingPathComponent(String(format: "%02d-%@.png", counter, name))
        try? screenshot.pngRepresentation.write(to: file)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 15) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("No aparece: \(what)")
            shot("FALLO-\(what)")
            return false
        }
        element.tap()
        return true
    }

    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Permitir al usar la app", "Permitir mientras se usa la app"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 4) {
                button.tap()
                return
            }
        }
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func testFullFlow() {
        app.launchArguments += ["-nexPlainPasswordField", "YES"]
        app.launch()

        // 1. Bienvenida y permiso de ubicación.
        XCTAssertTrue(app.staticTexts["NEX"].waitForExistence(timeout: 20))
        shot("bienvenida")
        tap(app.buttons["Permitir ubicación y empezar"], "botón de permiso")
        allowLocation()

        // 2. Mapa principal con los avisos sembrados.
        XCTAssertTrue(app.buttons["Buscar destino"].waitForExistence(timeout: 20), "No se llega al mapa")
        sleep(6)
        shot("mapa")

        // 3. Buscador.
        tap(app.buttons["Buscar destino"], "buscador")
        let field = app.searchFields.firstMatch
        tap(field, "campo de búsqueda")
        field.typeText("Estadio Santiago Bernabeu")
        let firstResult = app.collectionViews.buttons.element(boundBy: 0)
        XCTAssertTrue(firstResult.waitForExistence(timeout: 20), "La búsqueda no devuelve resultados")
        sleep(1)
        shot("busqueda")
        firstResult.tap()

        // 4. Vista previa de rutas.
        let startButton = app.buttons["Iniciar"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 40), "No se calculan rutas")
        sleep(2)
        shot("rutas")
        if app.buttons["Comparar con salir más tarde"].exists {
            app.buttons["Comparar con salir más tarde"].tap()
            sleep(8)
            shot("rutas-prevision")
        }

        // 5. Navegación activa.
        startButton.tap()
        XCTAssertTrue(app.buttons["Terminar navegación"].waitForExistence(timeout: 20), "No arranca la navegación")
        sleep(5)
        shot("navegacion")

        XCTAssertFalse(app.staticTexts["Buscando señal GPS…"].exists, "La guía no arranca con la última posición conocida")

        // 6. Reportar sin cuenta lleva al acceso.
        tap(app.buttons["Avisar de una incidencia"], "botón de avisar")
        XCTAssertTrue(app.staticTexts["Hace falta una cuenta"].waitForExistence(timeout: 10))
        shot("avisar-sin-cuenta")
        tap(app.buttons["Iniciar sesión o crear cuenta"], "acceso a cuenta")

        // 7. Formulario de registro (solo captura) e inicio de sesión con la cuenta sembrada por el CI.
        // El simulador tapa el campo de contraseña nueva con su sugerencia automática, así que el
        // alta completa no se puede automatizar aquí; la API de registro la cubren los tests del backend.
        tap(app.segmentedControls.buttons["Crear cuenta"], "pestaña de registro")
        sleep(1)
        shot("registro")
        tap(app.segmentedControls.buttons["Iniciar sesión"], "pestaña de acceso")
        let email = app.textFields["Correo electrónico"]
        tap(email, "campo correo")
        email.typeText("piloto@nex.test")
        let password = app.textFields["Contraseña"]
        tap(password, "campo contraseña")
        password.typeText("clave-de-siembra-1")
        shot("inicio-sesion")
        app.buttons.matching(identifier: "Iniciar sesión").allElementsBoundByIndex.last?.tap()
        for label in ["Not Now", "Ahora no"] where app.buttons[label].waitForExistence(timeout: 3) {
            app.buttons[label].tap()
        }
        let report = app.buttons["Avisar de una incidencia"]
        XCTAssertTrue(report.waitForExistence(timeout: 20), "El inicio de sesión no se completa")
        sleep(2)

        // 8. Reportar con cuenta.
        report.tap()
        XCTAssertTrue(app.buttons["Avisar de obras"].waitForExistence(timeout: 10), "No aparece el menú de avisos")
        shot("avisar")
        app.buttons["Avisar de obras"].tap()
        XCTAssertTrue(app.staticTexts["Gracias"].waitForExistence(timeout: 15), "El aviso no se envía")
        shot("aviso-enviado")
        sleep(3)

        // 9. Trayecto simulado: el CI mueve el simulador por Alcalá, Recoletos y la Castellana
        // cuando aparece este archivo.
        FileManager.default.createFile(atPath: shots.appendingPathComponent(".drive").path, contents: Data())
        let arrived = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Has llegado'")).firstMatch
        for second in [12, 30, 55, 85, 120] {
            if arrived.exists { break }
            sleep(UInt32(second == 12 ? 12 : 25))
            shot("conduccion-\(second)s")
        }
        if arrived.waitForExistence(timeout: 90) { shot("llegada") }

        // Fin de la navegación (con confirmación si no se ha llegado).
        tap(app.buttons["Terminar navegación"], "terminar")
        if app.buttons["Terminar"].waitForExistence(timeout: 3) { app.buttons["Terminar"].tap() }
        XCTAssertTrue(app.buttons["Buscar destino"].waitForExistence(timeout: 15))
        sleep(3)
        shot("mapa-tras-viaje")

        // 10. Resto de pantallas desde el menú.
        tap(app.buttons["Menú"], "menú")
        sleep(1)
        shot("menu")

        tap(app.buttons.containing(.staticText, identifier: "Perfil").firstMatch, "perfil")
        XCTAssertTrue(app.staticTexts["Piloto"].waitForExistence(timeout: 10), "El perfil no muestra al usuario")
        shot("perfil")
        back()

        tap(app.buttons.containing(.staticText, identifier: "Avisos cercanos").firstMatch, "avisos cercanos")
        sleep(2)
        shot("avisos-cercanos")
        let accident = app.buttons.containing(.staticText, identifier: "Accidente").firstMatch
        if accident.waitForExistence(timeout: 5) {
            accident.tap()
            sleep(1)
            shot("aviso-detalle")
            if app.buttons["Sigue ahí"].exists {
                app.buttons["Sigue ahí"].tap()
                sleep(3)
                shot("aviso-confirmado")
            }
            app.swipeDown(velocity: .fast)
            sleep(1)
        }
        back()

        tap(app.buttons.containing(.staticText, identifier: "Historial de viajes").firstMatch, "historial")
        sleep(1)
        shot("historial")
        back()

        tap(app.buttons.containing(.staticText, identifier: "Ajustes").firstMatch, "ajustes")
        sleep(1)
        shot("ajustes")
        tap(app.buttons["Configuración de avisos"], "configuración de avisos")
        sleep(1)
        shot("ajustes-avisos")
        back()
        tap(app.buttons["Mapas sin conexión"], "mapas sin conexión")
        sleep(1)
        shot("mapas-sin-conexion")
    }
}
