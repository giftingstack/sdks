import { createRoot } from "react-dom/client";
import App from "../../../examples/expo-demo/App";

// The Expo demo app ("Pixel") itself, run in the browser on react-native-web.
createRoot(document.getElementById("root")!).render(<App />);
