import { useState, useEffect, useRef, createContext, useContext } from "react";
import {
  Search, MapPin, BedDouble, Bath, Heart, Star, Menu, X,
  ArrowRight, Home, Building2, Users, ShieldCheck, Sparkles,
  Phone, Mail, Instagram, Twitter, Facebook, SlidersHorizontal,
  CheckCircle2, Clock, TrendingUp, LogIn, UserPlus, Eye, EyeOff,
  ChevronRight, LogOut, Bell, AlertCircle, RefreshCw, Lock,
  UserCheck, BarChart3, Settings, PlusCircle, Trash2, Edit3,
  ChevronDown, Shield, Zap, Key
} from "lucide-react";

// ─── Types ────────────────────────────────────────────────────────────────────

type Page =
  | "home" | "listings" | "detail" | "survey"
  | "login" | "register" | "otp" | "forgot"
  | "dashboard" | "admin";

type Role = "tenant" | "host" | "admin";

interface User {
  id: number;
  name: string;
  email: string;
  phone: string;
  role: Role;
  verified: boolean;
  avatar?: string;
}

interface Property {
  id: number;
  title: string;
  district: string;
  city: string;
  price: number;
  bedrooms: number;
  bathrooms: number;
  sqft: number;
  type: "apartment" | "house" | "studio" | "villa";
  image: string;
  rating: number;
  reviews: number;
  available: boolean;
  amenities: string[];
  host: string;
  hostId: number;
  approved: boolean;
  matchScore?: number;
}

interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
}

// ─── Auth Context ─────────────────────────────────────────────────────────────

const AuthContext = createContext<{
  auth: AuthState;
  login: (user: User, token: string) => void;
  logout: () => void;
}>({
  auth: { user: null, token: null, isAuthenticated: false },
  login: () => {},
  logout: () => {},
});

const useAuth = () => useContext(AuthContext);

// ─── Mock data ────────────────────────────────────────────────────────────────

const MOCK_USERS: Record<string, { user: User; password: string }> = {
  "amina@example.com": {
    password: "Password1",
    user: { id: 1, name: "Amina Kamau", email: "amina@example.com", phone: "+254712345678", role: "tenant", verified: true }
  },
  "deo@example.com": {
    password: "Password1",
    user: { id: 2, name: "Deo Otieno", email: "deo@example.com", phone: "+254723456789", role: "host", verified: true }
  },
  "admin@havenlink.co.ke": {
    password: "Admin123",
    user: { id: 3, name: "Admin User", email: "admin@havenlink.co.ke", phone: "+254700000000", role: "admin", verified: true }
  },
};

const PROPERTIES: Property[] = [
  {
    id: 1, title: "Serene Garden Apartment", district: "Kilimani", city: "Nairobi",
    price: 45000, bedrooms: 2, bathrooms: 2, sqft: 980, type: "apartment",
    image: "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800&h=540&fit=crop&auto=format",
    rating: 4.8, reviews: 34, available: true, approved: true, matchScore: 94,
    amenities: ["WiFi", "Parking", "Security", "Generator"], host: "Amara Osei", hostId: 2
  },
  {
    id: 2, title: "Modern Studio in Westlands", district: "Westlands", city: "Nairobi",
    price: 28000, bedrooms: 1, bathrooms: 1, sqft: 520, type: "studio",
    image: "https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800&h=540&fit=crop&auto=format",
    rating: 4.6, reviews: 21, available: true, approved: true, matchScore: 88,
    amenities: ["WiFi", "Gym", "Rooftop"], host: "Nasrin Mwangi", hostId: 2
  },
  {
    id: 3, title: "Lakeside Family Home", district: "Milimani", city: "Kisumu",
    price: 55000, bedrooms: 4, bathrooms: 3, sqft: 2100, type: "house",
    image: "https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=800&h=540&fit=crop&auto=format",
    rating: 4.9, reviews: 58, available: true, approved: true, matchScore: 91,
    amenities: ["Garden", "Parking", "Borehole", "CCTV"], host: "Deo Otieno", hostId: 2
  },
  {
    id: 4, title: "Executive 3BR Apartment", district: "Upper Hill", city: "Nairobi",
    price: 85000, bedrooms: 3, bathrooms: 2, sqft: 1400, type: "apartment",
    image: "https://images.unsplash.com/photo-1493809842364-78817add7ffb?w=800&h=540&fit=crop&auto=format",
    rating: 4.7, reviews: 29, available: false, approved: true, matchScore: 79,
    amenities: ["Concierge", "Pool", "Gym", "Parking"], host: "Beatrice Kamau", hostId: 2
  },
  {
    id: 5, title: "Coastal Villa with Ocean View", district: "Nyali", city: "Mombasa",
    price: 72000, bedrooms: 3, bathrooms: 3, sqft: 1800, type: "villa",
    image: "https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800&h=540&fit=crop&auto=format",
    rating: 5.0, reviews: 12, available: true, approved: false, matchScore: 96,
    amenities: ["Ocean view", "Pool", "Garden", "Security"], host: "Fatuma Ali", hostId: 2
  },
  {
    id: 6, title: "Compact Studio Near CBD", district: "Ngara", city: "Nairobi",
    price: 18000, bedrooms: 1, bathrooms: 1, sqft: 380, type: "studio",
    image: "https://images.unsplash.com/photo-1536376072261-38c75010e6c9?w=800&h=540&fit=crop&auto=format",
    rating: 4.3, reviews: 45, available: true, approved: true, matchScore: 72,
    amenities: ["WiFi", "Security"], host: "Peter Njoroge", hostId: 4
  },
];

const CITIES = ["All Cities", "Nairobi", "Mombasa", "Kisumu", "Nakuru"];
const TYPES = ["All Types", "Apartment", "House", "Studio", "Villa"];

// ─── Validation helpers ───────────────────────────────────────────────────────

const validate = {
  email: (v: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v) ? "" : "Enter a valid email address",
  password: (v: string) => v.length >= 8 ? "" : "Password must be at least 8 characters",
  phone: (v: string) => /^\+?[0-9]{10,13}$/.test(v.replace(/\s/g, "")) ? "" : "Enter a valid phone number",
  name: (v: string) => v.trim().length >= 2 ? "" : "Name must be at least 2 characters",
  required: (v: string) => v.trim() ? "" : "This field is required",
};

// ─── Shared UI ────────────────────────────────────────────────────────────────

function FieldError({ msg }: { msg: string }) {
  if (!msg) return null;
  return (
    <p className="flex items-center gap-1 text-xs text-destructive mt-1">
      <AlertCircle size={11} /> {msg}
    </p>
  );
}

function Toast({ message, type, onClose }: { message: string; type: "success" | "error"; onClose: () => void }) {
  useEffect(() => {
    const t = setTimeout(onClose, 3500);
    return () => clearTimeout(t);
  }, [onClose]);
  return (
    <div className={`fixed top-20 right-4 z-[100] flex items-center gap-3 px-4 py-3 rounded-lg shadow-lg text-sm font-medium transition-all ${type === "success" ? "bg-green-600 text-white" : "bg-destructive text-destructive-foreground"}`}>
      {type === "success" ? <CheckCircle2 size={15} /> : <AlertCircle size={15} />}
      {message}
      <button onClick={onClose} className="ml-2 opacity-70 hover:opacity-100"><X size={13} /></button>
    </div>
  );
}

// ─── Nav ──────────────────────────────────────────────────────────────────────

function Nav({ page, setPage }: { page: Page; setPage: (p: Page) => void }) {
  const { auth, logout } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setUserMenuOpen(false);
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  const navLinks = [
    { label: "Find a Home", p: "listings" as Page },
    { label: "Haven Survey", p: "survey" as Page },
    ...(auth.user?.role === "admin" ? [{ label: "Admin", p: "admin" as Page }] : []),
    ...(auth.isAuthenticated ? [{ label: "Dashboard", p: "dashboard" as Page }] : []),
  ];

  function handleLogout() {
    logout();
    setUserMenuOpen(false);
    setPage("home");
  }

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-card/95 backdrop-blur-sm border-b border-border">
      <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
        <button onClick={() => setPage("home")} className="flex items-center gap-2.5">
          <div className="w-8 h-8 bg-primary rounded-sm flex items-center justify-center">
            <Home size={16} className="text-primary-foreground" />
          </div>
          <span className="font-['Playfair_Display'] text-xl font-semibold text-foreground">
            Haven<span className="text-accent">Link</span>
          </span>
        </button>

        <div className="hidden md:flex items-center gap-8">
          {navLinks.map(({ label, p }) => (
            <button key={p} onClick={() => setPage(p)}
              className={`text-sm transition-colors ${page === p ? "text-primary font-medium" : "text-muted-foreground hover:text-foreground"}`}>
              {label}
            </button>
          ))}
        </div>

        <div className="hidden md:flex items-center gap-3">
          {auth.isAuthenticated && auth.user ? (
            <div className="relative" ref={menuRef}>
              <button
                onClick={() => setUserMenuOpen(!userMenuOpen)}
                className="flex items-center gap-2.5 border border-border rounded-full pl-1 pr-3 py-1 hover:bg-muted transition-colors"
              >
                <div className="w-7 h-7 rounded-full bg-primary flex items-center justify-center text-primary-foreground text-xs font-bold">
                  {auth.user.name.charAt(0)}
                </div>
                <span className="text-sm font-medium">{auth.user.name.split(" ")[0]}</span>
                <ChevronDown size={13} className="text-muted-foreground" />
              </button>
              {userMenuOpen && (
                <div className="absolute right-0 top-full mt-2 w-52 bg-card rounded-lg border border-border shadow-xl py-1 z-50">
                  <div className="px-4 py-2.5 border-b border-border">
                    <p className="text-xs font-semibold">{auth.user.name}</p>
                    <p className="text-xs text-muted-foreground">{auth.user.email}</p>
                    <span className={`text-xs px-2 py-0.5 rounded-full mt-1 inline-block font-medium capitalize
                      ${auth.user.role === "admin" ? "bg-purple-100 text-purple-700" :
                        auth.user.role === "host" ? "bg-blue-100 text-blue-700" :
                        "bg-green-100 text-green-700"}`}>
                      {auth.user.role}
                    </span>
                  </div>
                  {[
                    { label: "Dashboard", icon: <BarChart3 size={13} />, action: () => { setPage("dashboard"); setUserMenuOpen(false); } },
                    ...(auth.user.role === "admin" ? [{ label: "Admin Panel", icon: <Shield size={13} />, action: () => { setPage("admin"); setUserMenuOpen(false); } }] : []),
                    { label: "Settings", icon: <Settings size={13} />, action: () => { setPage("dashboard"); setUserMenuOpen(false); } },
                  ].map(({ label, icon, action }) => (
                    <button key={label} onClick={action}
                      className="w-full flex items-center gap-3 px-4 py-2.5 text-sm hover:bg-muted transition-colors text-left">
                      <span className="text-muted-foreground">{icon}</span>{label}
                    </button>
                  ))}
                  <div className="border-t border-border mt-1">
                    <button onClick={handleLogout}
                      className="w-full flex items-center gap-3 px-4 py-2.5 text-sm hover:bg-muted transition-colors text-left text-destructive">
                      <LogOut size={13} /> Sign Out
                    </button>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <>
              <button onClick={() => setPage("login")}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors px-4 py-2">
                Sign in
              </button>
              <button onClick={() => setPage("register")}
                className="text-sm bg-primary text-primary-foreground px-4 py-2 rounded hover:opacity-90 transition-opacity">
                Get Started
              </button>
            </>
          )}
        </div>

        <button className="md:hidden" onClick={() => setMobileOpen(!mobileOpen)}>
          {mobileOpen ? <X size={20} /> : <Menu size={20} />}
        </button>
      </div>

      {mobileOpen && (
        <div className="md:hidden border-t border-border bg-card px-6 py-4 flex flex-col gap-4">
          {navLinks.map(({ label, p }) => (
            <button key={p} onClick={() => { setPage(p); setMobileOpen(false); }}
              className="text-sm text-left text-foreground py-1">{label}</button>
          ))}
          <div className="flex gap-3 pt-2 border-t border-border">
            {auth.isAuthenticated ? (
              <button onClick={() => { handleLogout(); setMobileOpen(false); }}
                className="flex-1 text-sm border border-border rounded py-2 text-destructive">Sign Out</button>
            ) : (
              <>
                <button onClick={() => { setPage("login"); setMobileOpen(false); }}
                  className="flex-1 text-sm border border-border rounded py-2">Sign in</button>
                <button onClick={() => { setPage("register"); setMobileOpen(false); }}
                  className="flex-1 text-sm bg-primary text-primary-foreground rounded py-2">Register</button>
              </>
            )}
          </div>
        </div>
      )}
    </nav>
  );
}

// ─── Property Card ────────────────────────────────────────────────────────────

function PropertyCard({ p, onClick, favorited, onFav }: {
  p: Property; onClick: () => void; favorited: boolean; onFav: () => void;
}) {
  return (
    <div onClick={onClick}
      className="bg-card rounded-lg overflow-hidden border border-border hover:shadow-lg hover:-translate-y-0.5 transition-all duration-200 cursor-pointer group">
      <div className="relative overflow-hidden aspect-[4/3] bg-muted">
        <img src={p.image} alt={p.title} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />
        <div className="absolute inset-0 bg-gradient-to-t from-black/30 to-transparent" />
        {!p.available && (
          <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
            <span className="bg-card text-foreground text-xs font-medium px-3 py-1 rounded">Not Available</span>
          </div>
        )}
        <button onClick={e => { e.stopPropagation(); onFav(); }}
          className={`absolute top-3 right-3 w-8 h-8 rounded-full flex items-center justify-center transition-all ${favorited ? "bg-red-500 text-white" : "bg-white/90 text-muted-foreground hover:text-red-500"}`}>
          <Heart size={15} fill={favorited ? "currentColor" : "none"} />
        </button>
        {p.matchScore && (
          <div className="absolute top-3 left-3 bg-accent text-accent-foreground text-xs font-semibold px-2 py-1 rounded flex items-center gap-1">
            <Sparkles size={11} />{p.matchScore}% match
          </div>
        )}
        <div className="absolute bottom-3 left-3 text-white text-xs flex items-center gap-1">
          <MapPin size={11} />{p.district}, {p.city}
        </div>
      </div>
      <div className="p-4">
        <div className="flex items-start justify-between gap-2 mb-2">
          <h3 className="font-['Playfair_Display'] text-base font-semibold text-card-foreground leading-tight">{p.title}</h3>
          <div className="flex items-center gap-1 shrink-0">
            <Star size={12} fill="#C8A96E" stroke="none" /><span className="text-xs text-muted-foreground">{p.rating}</span>
          </div>
        </div>
        <div className="flex items-center gap-3 text-xs text-muted-foreground mb-3">
          <span className="flex items-center gap-1"><BedDouble size={12} />{p.bedrooms} bd</span>
          <span className="flex items-center gap-1"><Bath size={12} />{p.bathrooms} ba</span>
          <span>{p.sqft.toLocaleString()} sq ft</span>
        </div>
        <div className="flex items-center justify-between">
          <div>
            <span className="text-lg font-semibold text-primary">KSh {p.price.toLocaleString()}</span>
            <span className="text-xs text-muted-foreground">/mo</span>
          </div>
          <span className={`text-xs px-2 py-0.5 rounded-full ${p.available ? "bg-green-100 text-green-700" : "bg-muted text-muted-foreground"}`}>
            {p.available ? "Available" : "Taken"}
          </span>
        </div>
      </div>
    </div>
  );
}

// ─── Auth Pages ───────────────────────────────────────────────────────────────

function LoginPage({ setPage }: { setPage: (p: Page) => void }) {
  const { login } = useAuth();
  const [form, setForm] = useState({ email: "", password: "" });
  const [errors, setErrors] = useState({ email: "", password: "", general: "" });
  const [showPw, setShowPw] = useState(false);
  const [loading, setLoading] = useState(false);
  const [toast, setToast] = useState<{ msg: string; type: "success" | "error" } | null>(null);

  const field = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => {
    setForm(f => ({ ...f, [k]: e.target.value }));
    setErrors(er => ({ ...er, [k]: "", general: "" }));
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const emailErr = validate.email(form.email);
    const pwErr = validate.required(form.password);
    if (emailErr || pwErr) { setErrors({ email: emailErr, password: pwErr, general: "" }); return; }

    setLoading(true);
    await new Promise(r => setTimeout(r, 900));

    const record = MOCK_USERS[form.email.toLowerCase()];
    if (!record || record.password !== form.password) {
      setErrors({ email: "", password: "", general: "Invalid email or password. Try amina@example.com / Password1" });
      setLoading(false);
      return;
    }

    login(record.user, "mock-jwt-token-" + Date.now());
    setToast({ msg: `Welcome back, ${record.user.name.split(" ")[0]}!`, type: "success" });
    setTimeout(() => {
      setPage(record.user.role === "admin" ? "admin" : "dashboard");
    }, 800);
    setLoading(false);
  }

  return (
    <div className="min-h-screen pt-20 flex">
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
      <div className="hidden md:block w-1/2 relative overflow-hidden">
        <img src="https://images.unsplash.com/photo-1565402170291-8491f14678db?w=900&h=1200&fit=crop&auto=format"
          alt="Modern home interior" className="w-full h-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-r from-primary/85 to-primary/40" />
        <div className="absolute inset-0 flex flex-col justify-end p-12">
          <div className="flex items-center gap-2 mb-8">
            <div className="w-8 h-8 bg-white/20 rounded flex items-center justify-center">
              <Home size={15} className="text-white" />
            </div>
            <span className="font-['Playfair_Display'] text-xl font-semibold text-white">HavenLink</span>
          </div>
          <blockquote className="text-white">
            <p className="text-xl font-['Playfair_Display'] leading-relaxed mb-4">
              "Haven Link found me an apartment in Kilimani that matched 94% of my criteria —
              I moved in within two weeks."
            </p>
            <footer className="text-white/70 text-sm">— Amina K., Nairobi tenant</footer>
          </blockquote>
          <div className="mt-8 p-4 bg-white/10 backdrop-blur-sm rounded-lg border border-white/20">
            <p className="text-white/60 text-xs mb-2 font-medium uppercase tracking-wide">Demo credentials</p>
            <div className="space-y-1 text-xs text-white/80 font-['DM_Mono',_monospace]">
              <p>Tenant: amina@example.com / Password1</p>
              <p>Host: deo@example.com / Password1</p>
              <p>Admin: admin@havenlink.co.ke / Admin123</p>
            </div>
          </div>
        </div>
      </div>

      <div className="w-full md:w-1/2 flex items-center justify-center p-8 bg-background">
        <div className="w-full max-w-md">
          <div className="mb-8">
            <h1 className="text-3xl font-['Playfair_Display'] font-semibold mb-2">Welcome back</h1>
            <p className="text-muted-foreground text-sm">Sign in to your Haven Link account.</p>
          </div>

          <form onSubmit={handleSubmit} noValidate className="space-y-5">
            {errors.general && (
              <div className="flex items-start gap-2.5 bg-destructive/10 border border-destructive/20 text-destructive rounded-lg px-4 py-3 text-sm">
                <AlertCircle size={15} className="mt-0.5 shrink-0" />{errors.general}
              </div>
            )}

            <div>
              <label className="text-sm font-medium block mb-1.5">Email Address</label>
              <input type="email" value={form.email} onChange={field("email")} placeholder="amina@example.com"
                className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring transition-colors ${errors.email ? "border-destructive" : "border-border"}`} />
              <FieldError msg={errors.email} />
            </div>

            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label className="text-sm font-medium">Password</label>
                <button type="button" onClick={() => setPage("forgot")}
                  className="text-xs text-primary hover:underline">Forgot password?</button>
              </div>
              <div className="relative">
                <input type={showPw ? "text" : "password"} value={form.password} onChange={field("password")}
                  placeholder="Your password"
                  className={`w-full bg-input-background border rounded px-4 py-2.5 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-ring transition-colors ${errors.password ? "border-destructive" : "border-border"}`} />
                <button type="button" onClick={() => setShowPw(!showPw)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                  {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                </button>
              </div>
              <FieldError msg={errors.password} />
            </div>

            <button type="submit" disabled={loading}
              className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 transition-opacity flex items-center justify-center gap-2 disabled:opacity-60">
              {loading ? <><RefreshCw size={15} className="animate-spin" /> Signing in…</> : <><LogIn size={15} /> Sign In</>}
            </button>
          </form>

          <p className="text-center text-sm text-muted-foreground mt-6">
            {"Don't have an account? "}
            <button onClick={() => setPage("register")} className="text-primary font-medium hover:underline">Sign up free</button>
          </p>
        </div>
      </div>
    </div>
  );
}

function RegisterPage({ setPage }: { setPage: (p: Page) => void }) {
  const [role, setRole] = useState<"tenant" | "host">("tenant");
  const [form, setForm] = useState({ name: "", email: "", phone: "", password: "", confirmPassword: "" });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [showPw, setShowPw] = useState(false);
  const [loading, setLoading] = useState(false);
  const [agreed, setAgreed] = useState(false);

  const field = (k: string) => (e: React.ChangeEvent<HTMLInputElement>) => {
    setForm(f => ({ ...f, [k]: e.target.value }));
    setErrors(er => { const n = { ...er }; delete n[k]; return n; });
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const errs: Record<string, string> = {};
    const nameErr = validate.name(form.name); if (nameErr) errs.name = nameErr;
    const emailErr = validate.email(form.email); if (emailErr) errs.email = emailErr;
    const phoneErr = validate.phone(form.phone); if (phoneErr) errs.phone = phoneErr;
    const pwErr = validate.password(form.password); if (pwErr) errs.password = pwErr;
    if (form.password !== form.confirmPassword) errs.confirmPassword = "Passwords do not match";
    if (!agreed) errs.agreed = "You must agree to the terms";
    if (Object.keys(errs).length) { setErrors(errs); return; }

    setLoading(true);
    await new Promise(r => setTimeout(r, 1000));
    setLoading(false);
    setPage("otp");
  }

  const pwStrength = (() => {
    const p = form.password;
    let s = 0;
    if (p.length >= 8) s++;
    if (/[A-Z]/.test(p)) s++;
    if (/[0-9]/.test(p)) s++;
    if (/[^A-Za-z0-9]/.test(p)) s++;
    return s;
  })();

  const strengthLabel = ["", "Weak", "Fair", "Good", "Strong"][pwStrength];
  const strengthColor = ["", "bg-red-500", "bg-amber-500", "bg-blue-500", "bg-green-500"][pwStrength];

  return (
    <div className="min-h-screen pt-20 flex">
      <div className="hidden md:block w-5/12 relative overflow-hidden">
        <img src="https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=900&h=1200&fit=crop&auto=format"
          alt="Nairobi apartments" className="w-full h-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-r from-primary/85 to-primary/30" />
        <div className="absolute inset-0 flex flex-col justify-center p-12">
          <h2 className="font-['Playfair_Display'] text-3xl text-white font-semibold mb-6 leading-tight">
            Join 12,000+<br />East Africans<br />finding home.
          </h2>
          {[
            { icon: <Sparkles size={16} />, text: "AI-matched listings in seconds" },
            { icon: <ShieldCheck size={16} />, text: "Verified hosts & properties only" },
            { icon: <Zap size={16} />, text: "Book visits without phone calls" },
          ].map(({ icon, text }) => (
            <div key={text} className="flex items-center gap-3 mb-4 text-white/90 text-sm">
              <div className="w-7 h-7 bg-white/15 rounded flex items-center justify-center shrink-0">{icon}</div>
              {text}
            </div>
          ))}
        </div>
      </div>

      <div className="w-full md:w-7/12 flex items-center justify-center p-8 bg-background overflow-y-auto">
        <div className="w-full max-w-md py-8">
          <div className="mb-6">
            <h1 className="text-3xl font-['Playfair_Display'] font-semibold mb-2">Create your account</h1>
            <p className="text-muted-foreground text-sm">Start finding your perfect home in East Africa.</p>
          </div>

          <div className="flex gap-2 mb-6 bg-muted p-1 rounded-lg">
            {(["tenant", "host"] as const).map(r => (
              <button key={r} onClick={() => setRole(r)}
                className={`flex-1 py-2 rounded text-sm font-medium capitalize transition-all ${role === r ? "bg-card shadow text-foreground" : "text-muted-foreground"}`}>
                {r === "tenant" ? "🏠 I'm a Tenant" : "🔑 I'm a Host"}
              </button>
            ))}
          </div>

          <form onSubmit={handleSubmit} noValidate className="space-y-4">
            <div>
              <label className="text-sm font-medium block mb-1.5">Full Name</label>
              <input value={form.name} onChange={field("name")} placeholder="Amina Kamau"
                className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${errors.name ? "border-destructive" : "border-border"}`} />
              <FieldError msg={errors.name || ""} />
            </div>
            <div>
              <label className="text-sm font-medium block mb-1.5">Email Address</label>
              <input type="email" value={form.email} onChange={field("email")} placeholder="amina@example.com"
                className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${errors.email ? "border-destructive" : "border-border"}`} />
              <FieldError msg={errors.email || ""} />
            </div>
            <div>
              <label className="text-sm font-medium block mb-1.5">Phone Number</label>
              <input type="tel" value={form.phone} onChange={field("phone")} placeholder="+254 712 345 678"
                className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${errors.phone ? "border-destructive" : "border-border"}`} />
              <FieldError msg={errors.phone || ""} />
            </div>
            <div>
              <label className="text-sm font-medium block mb-1.5">Password</label>
              <div className="relative">
                <input type={showPw ? "text" : "password"} value={form.password} onChange={field("password")}
                  placeholder="At least 8 characters"
                  className={`w-full bg-input-background border rounded px-4 py-2.5 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${errors.password ? "border-destructive" : "border-border"}`} />
                <button type="button" onClick={() => setShowPw(!showPw)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                  {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                </button>
              </div>
              {form.password && (
                <div className="flex items-center gap-2 mt-1.5">
                  <div className="flex gap-0.5 flex-1">
                    {[1,2,3,4].map(i => (
                      <div key={i} className={`h-1 flex-1 rounded-full transition-colors ${i <= pwStrength ? strengthColor : "bg-muted"}`} />
                    ))}
                  </div>
                  <span className="text-xs text-muted-foreground">{strengthLabel}</span>
                </div>
              )}
              <FieldError msg={errors.password || ""} />
            </div>
            <div>
              <label className="text-sm font-medium block mb-1.5">Confirm Password</label>
              <input type="password" value={form.confirmPassword} onChange={field("confirmPassword")}
                placeholder="Repeat your password"
                className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${errors.confirmPassword ? "border-destructive" : "border-border"}`} />
              <FieldError msg={errors.confirmPassword || ""} />
            </div>

            <div className="flex items-start gap-3 pt-1">
              <button type="button" onClick={() => { setAgreed(!agreed); setErrors(er => { const n = {...er}; delete n.agreed; return n; }); }}
                className={`w-4.5 h-4.5 mt-0.5 rounded border-2 shrink-0 flex items-center justify-center transition-colors ${agreed ? "bg-primary border-primary" : "border-border"}`}>
                {agreed && <CheckCircle2 size={11} className="text-primary-foreground" />}
              </button>
              <p className="text-xs text-muted-foreground leading-relaxed">
                I agree to Haven Link's{" "}
                <a href="#" className="text-primary hover:underline">Terms of Service</a> and{" "}
                <a href="#" className="text-primary hover:underline">Privacy Policy</a>. I consent to receiving SMS updates about my bookings.
              </p>
            </div>
            {errors.agreed && <FieldError msg={errors.agreed} />}

            <button type="submit" disabled={loading}
              className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 transition-opacity flex items-center justify-center gap-2 disabled:opacity-60 mt-2">
              {loading ? <><RefreshCw size={15} className="animate-spin" /> Creating account…</> : <><UserPlus size={15} /> Create Account</>}
            </button>
          </form>

          <p className="text-center text-sm text-muted-foreground mt-6">
            Already have an account?{" "}
            <button onClick={() => setPage("login")} className="text-primary font-medium hover:underline">Sign in</button>
          </p>
        </div>
      </div>
    </div>
  );
}

function OTPPage({ setPage }: { setPage: (p: Page) => void }) {
  const [otp, setOtp] = useState(["", "", "", "", "", ""]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [resent, setResent] = useState(false);
  const [countdown, setCountdown] = useState(30);
  const inputs = useRef<(HTMLInputElement | null)[]>([]);

  useEffect(() => {
    if (countdown > 0) {
      const t = setTimeout(() => setCountdown(c => c - 1), 1000);
      return () => clearTimeout(t);
    }
  }, [countdown]);

  function handleChange(i: number, v: string) {
    const clean = v.replace(/\D/g, "").slice(0, 1);
    const next = [...otp];
    next[i] = clean;
    setOtp(next);
    setError("");
    if (clean && i < 5) inputs.current[i + 1]?.focus();
  }

  function handleKey(i: number, e: React.KeyboardEvent) {
    if (e.key === "Backspace" && !otp[i] && i > 0) inputs.current[i - 1]?.focus();
  }

  function handlePaste(e: React.ClipboardEvent) {
    const text = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
    if (text.length === 6) {
      setOtp(text.split(""));
      inputs.current[5]?.focus();
    }
  }

  async function handleVerify() {
    const code = otp.join("");
    if (code.length < 6) { setError("Enter all 6 digits"); return; }
    setLoading(true);
    await new Promise(r => setTimeout(r, 1000));
    if (code === "123456") {
      setPage("login");
    } else {
      setError("Incorrect OTP. Use 123456 for demo.");
    }
    setLoading(false);
  }

  async function handleResend() {
    setResent(true);
    setCountdown(30);
    setOtp(["", "", "", "", "", ""]);
    inputs.current[0]?.focus();
    await new Promise(r => setTimeout(r, 500));
  }

  return (
    <div className="min-h-screen pt-20 flex items-center justify-center bg-secondary px-6">
      <div className="w-full max-w-md">
        <div className="bg-card rounded-2xl border border-border p-10 text-center shadow-lg">
          <div className="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-6">
            <Key size={28} className="text-primary" />
          </div>
          <h1 className="text-2xl font-['Playfair_Display'] font-semibold mb-2">Verify your phone</h1>
          <p className="text-muted-foreground text-sm mb-2">
            We sent a 6-digit code to your phone number.
          </p>
          <p className="text-xs text-muted-foreground mb-8">
            <span className="font-medium text-foreground">+254 7** *** 678</span>
          </p>

          <div className="flex gap-2 justify-center mb-2" onPaste={handlePaste}>
            {otp.map((digit, i) => (
              <input
                key={i}
                ref={el => { inputs.current[i] = el; }}
                type="text"
                inputMode="numeric"
                maxLength={1}
                value={digit}
                onChange={e => handleChange(i, e.target.value)}
                onKeyDown={e => handleKey(i, e)}
                className={`w-11 h-13 text-center text-xl font-bold bg-input-background border-2 rounded-lg focus:outline-none transition-colors
                  ${digit ? "border-primary text-primary" : "border-border text-foreground"}
                  ${error ? "border-destructive" : ""}`}
                style={{ height: "3.25rem" }}
              />
            ))}
          </div>

          {error && <p className="text-xs text-destructive flex items-center justify-center gap-1 mb-4"><AlertCircle size={11} />{error}</p>}

          <p className="text-xs text-muted-foreground mb-6">Hint: use <span className="font-mono font-semibold text-foreground">123456</span></p>

          <button onClick={handleVerify} disabled={loading || otp.join("").length < 6}
            className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 transition-opacity flex items-center justify-center gap-2 disabled:opacity-50 mb-4">
            {loading ? <><RefreshCw size={15} className="animate-spin" /> Verifying…</> : <><UserCheck size={15} /> Verify Account</>}
          </button>

          <div className="text-sm text-muted-foreground">
            {"Didn't receive the code? "}
            {countdown > 0 ? (
              <span className="text-foreground font-medium">Resend in {countdown}s</span>
            ) : (
              <button onClick={handleResend} className="text-primary font-medium hover:underline flex items-center gap-1 inline-flex">
                <RefreshCw size={12} /> Resend OTP
              </button>
            )}
          </div>

          {resent && (
            <p className="text-xs text-green-600 flex items-center justify-center gap-1 mt-3">
              <CheckCircle2 size={12} /> OTP resent successfully
            </p>
          )}
        </div>

        <button onClick={() => setPage("register")}
          className="mt-4 w-full text-sm text-muted-foreground text-center hover:text-foreground transition-colors">
          ← Back to registration
        </button>
      </div>
    </div>
  );
}

function ForgotPasswordPage({ setPage }: { setPage: (p: Page) => void }) {
  const [step, setStep] = useState<"email" | "otp" | "reset" | "done">("email");
  const [email, setEmail] = useState("");
  const [emailErr, setEmailErr] = useState("");
  const [otp, setOtp] = useState(["", "", "", "", "", ""]);
  const [otpErr, setOtpErr] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [pwErr, setPwErr] = useState("");
  const [loading, setLoading] = useState(false);
  const inputs = useRef<(HTMLInputElement | null)[]>([]);

  async function sendReset(e: React.FormEvent) {
    e.preventDefault();
    const err = validate.email(email);
    if (err) { setEmailErr(err); return; }
    setLoading(true);
    await new Promise(r => setTimeout(r, 900));
    setLoading(false);
    setStep("otp");
  }

  async function verifyOtp() {
    const code = otp.join("");
    if (code.length < 6) { setOtpErr("Enter all 6 digits"); return; }
    setLoading(true);
    await new Promise(r => setTimeout(r, 800));
    if (code !== "123456") { setOtpErr("Incorrect code. Use 123456."); setLoading(false); return; }
    setLoading(false);
    setStep("reset");
  }

  async function resetPassword(e: React.FormEvent) {
    e.preventDefault();
    const err = validate.password(password);
    if (err) { setPwErr(err); return; }
    if (password !== confirm) { setPwErr("Passwords do not match"); return; }
    setLoading(true);
    await new Promise(r => setTimeout(r, 900));
    setLoading(false);
    setStep("done");
  }

  function handleOtpChange(i: number, v: string) {
    const clean = v.replace(/\D/g, "").slice(0, 1);
    const next = [...otp]; next[i] = clean; setOtp(next); setOtpErr("");
    if (clean && i < 5) inputs.current[i + 1]?.focus();
  }

  return (
    <div className="min-h-screen pt-20 flex items-center justify-center bg-secondary px-6">
      <div className="w-full max-w-md">
        <div className="bg-card rounded-2xl border border-border p-10 shadow-lg">
          <div className="text-center mb-8">
            <div className="w-14 h-14 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <Lock size={24} className="text-primary" />
            </div>
            <h1 className="text-2xl font-['Playfair_Display'] font-semibold mb-1">
              {step === "done" ? "Password Reset!" : "Reset Password"}
            </h1>
            <p className="text-muted-foreground text-sm">
              {step === "email" && "Enter your email and we'll send a reset code."}
              {step === "otp" && `Code sent to ${email}`}
              {step === "reset" && "Choose a strong new password."}
              {step === "done" && "Your password has been updated."}
            </p>
          </div>

          <div className="flex justify-between mb-8">
            {["email", "otp", "reset"].map((s, i) => (
              <div key={s} className="flex items-center flex-1">
                <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-semibold transition-colors
                  ${["email","otp","reset","done"].indexOf(step) > i ? "bg-primary text-primary-foreground" :
                    step === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>
                  {["email","otp","reset","done"].indexOf(step) > i ? <CheckCircle2 size={14} /> : i + 1}
                </div>
                {i < 2 && <div className={`flex-1 h-0.5 mx-1 rounded ${["email","otp","reset","done"].indexOf(step) > i ? "bg-primary" : "bg-muted"}`} />}
              </div>
            ))}
          </div>

          {step === "email" && (
            <form onSubmit={sendReset} className="space-y-4">
              <div>
                <label className="text-sm font-medium block mb-1.5">Email Address</label>
                <input type="email" value={email} onChange={e => { setEmail(e.target.value); setEmailErr(""); }}
                  placeholder="amina@example.com"
                  className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${emailErr ? "border-destructive" : "border-border"}`} />
                <FieldError msg={emailErr} />
              </div>
              <button type="submit" disabled={loading}
                className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 flex items-center justify-center gap-2 disabled:opacity-60">
                {loading ? <><RefreshCw size={15} className="animate-spin" /> Sending…</> : "Send Reset Code"}
              </button>
            </form>
          )}

          {step === "otp" && (
            <div>
              <div className="flex gap-2 justify-center mb-4">
                {otp.map((d, i) => (
                  <input key={i} ref={el => { inputs.current[i] = el; }} type="text" inputMode="numeric"
                    maxLength={1} value={d} onChange={e => handleOtpChange(i, e.target.value)}
                    onKeyDown={e => { if (e.key === "Backspace" && !d && i > 0) inputs.current[i-1]?.focus(); }}
                    className={`w-11 text-center text-xl font-bold bg-input-background border-2 rounded-lg focus:outline-none transition-colors ${d ? "border-primary" : "border-border"}`}
                    style={{ height: "3.25rem" }} />
                ))}
              </div>
              {otpErr && <p className="text-xs text-destructive text-center mb-3 flex items-center justify-center gap-1"><AlertCircle size={11} />{otpErr}</p>}
              <p className="text-xs text-center text-muted-foreground mb-4">Hint: <span className="font-mono font-semibold text-foreground">123456</span></p>
              <button onClick={verifyOtp} disabled={loading}
                className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 flex items-center justify-center gap-2 disabled:opacity-60">
                {loading ? <><RefreshCw size={15} className="animate-spin" /> Verifying…</> : "Verify Code"}
              </button>
            </div>
          )}

          {step === "reset" && (
            <form onSubmit={resetPassword} className="space-y-4">
              <div>
                <label className="text-sm font-medium block mb-1.5">New Password</label>
                <input type="password" value={password} onChange={e => { setPassword(e.target.value); setPwErr(""); }}
                  placeholder="At least 8 characters"
                  className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${pwErr ? "border-destructive" : "border-border"}`} />
              </div>
              <div>
                <label className="text-sm font-medium block mb-1.5">Confirm Password</label>
                <input type="password" value={confirm} onChange={e => { setConfirm(e.target.value); setPwErr(""); }}
                  placeholder="Repeat new password"
                  className={`w-full bg-input-background border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring ${pwErr ? "border-destructive" : "border-border"}`} />
                <FieldError msg={pwErr} />
              </div>
              <button type="submit" disabled={loading}
                className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90 flex items-center justify-center gap-2 disabled:opacity-60">
                {loading ? <><RefreshCw size={15} className="animate-spin" /> Updating…</> : "Reset Password"}
              </button>
            </form>
          )}

          {step === "done" && (
            <div className="text-center">
              <div className="w-14 h-14 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <CheckCircle2 size={28} className="text-green-600" />
              </div>
              <p className="text-sm text-muted-foreground mb-6">You can now sign in with your new password.</p>
              <button onClick={() => setPage("login")}
                className="w-full bg-primary text-primary-foreground py-3 rounded font-medium hover:opacity-90">
                Go to Sign In
              </button>
            </div>
          )}
        </div>
        {step !== "done" && (
          <button onClick={() => setPage("login")}
            className="mt-4 w-full text-sm text-muted-foreground text-center hover:text-foreground transition-colors">
            ← Back to sign in
          </button>
        )}
      </div>
    </div>
  );
}

// ─── Listings ─────────────────────────────────────────────────────────────────

function ListingsPage({ setPage, setSelectedProperty }: {
  setPage: (p: Page) => void;
  setSelectedProperty: (p: Property) => void;
}) {
  const [favorites, setFavorites] = useState<number[]>([]);
  const [city, setCity] = useState("All Cities");
  const [type, setType] = useState("All Types");
  const [maxPrice, setMaxPrice] = useState(100000);
  const [minBeds, setMinBeds] = useState(0);
  const [showFilters, setShowFilters] = useState(false);
  const [sortBy, setSortBy] = useState("match");
  const [search, setSearch] = useState("");

  const filtered = PROPERTIES
    .filter(p => p.approved)
    .filter(p =>
      (city === "All Cities" || p.city === city) &&
      (type === "All Types" || p.type === type.toLowerCase()) &&
      p.price <= maxPrice && p.bedrooms >= minBeds &&
      (search === "" || p.title.toLowerCase().includes(search.toLowerCase()) || p.district.toLowerCase().includes(search.toLowerCase()))
    )
    .sort((a, b) => {
      if (sortBy === "match") return (b.matchScore || 0) - (a.matchScore || 0);
      if (sortBy === "price_asc") return a.price - b.price;
      if (sortBy === "price_desc") return b.price - a.price;
      return b.rating - a.rating;
    });

  const toggleFav = (id: number) =>
    setFavorites(f => f.includes(id) ? f.filter(x => x !== id) : [...f, id]);

  return (
    <div className="min-h-screen pt-20">
      <div className="bg-card border-b border-border sticky top-16 z-40">
        <div className="max-w-7xl mx-auto px-6 py-3 flex items-center gap-3 flex-wrap">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search district…"
              className="bg-input-background border border-border rounded pl-8 pr-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring w-40" />
          </div>
          <select value={city} onChange={e => setCity(e.target.value)}
            className="bg-input-background border border-border rounded px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring">
            {CITIES.map(c => <option key={c}>{c}</option>)}
          </select>
          <select value={type} onChange={e => setType(e.target.value)}
            className="bg-input-background border border-border rounded px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring">
            {TYPES.map(t => <option key={t}>{t}</option>)}
          </select>
          <button onClick={() => setShowFilters(!showFilters)}
            className={`flex items-center gap-2 px-3 py-1.5 rounded border text-sm transition-colors ${showFilters ? "bg-primary text-primary-foreground border-primary" : "bg-input-background border-border hover:border-primary"}`}>
            <SlidersHorizontal size={14} />Filters
          </button>
          <div className="ml-auto flex items-center gap-2">
            <span className="text-xs text-muted-foreground">{filtered.length} results</span>
            <select value={sortBy} onChange={e => setSortBy(e.target.value)}
              className="bg-input-background border border-border rounded px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring">
              <option value="match">Best Match</option>
              <option value="price_asc">Price: Low–High</option>
              <option value="price_desc">Price: High–Low</option>
              <option value="rating">Top Rated</option>
            </select>
          </div>
        </div>
        {showFilters && (
          <div className="border-t border-border bg-secondary/50">
            <div className="max-w-7xl mx-auto px-6 py-4 flex gap-8 flex-wrap">
              <div>
                <label className="text-xs text-muted-foreground block mb-1">Max Price: KSh {maxPrice.toLocaleString()}</label>
                <input type="range" min={10000} max={100000} step={5000} value={maxPrice}
                  onChange={e => setMaxPrice(Number(e.target.value))} className="w-40 accent-primary" />
              </div>
              <div>
                <label className="text-xs text-muted-foreground block mb-1">Min Bedrooms: {minBeds}</label>
                <input type="range" min={0} max={4} step={1} value={minBeds}
                  onChange={e => setMinBeds(Number(e.target.value))} className="w-32 accent-primary" />
              </div>
            </div>
          </div>
        )}
      </div>
      <div className="max-w-7xl mx-auto px-6 py-8">
        <div className="mb-6">
          <h1 className="text-2xl font-['Playfair_Display'] font-semibold mb-1">
            {city === "All Cities" ? "All Properties" : `Properties in ${city}`}
          </h1>
          <p className="text-muted-foreground text-sm">{filtered.length} homes · sorted by {sortBy === "match" ? "Haven Match" : sortBy.replace("_", " ")}</p>
        </div>
        {filtered.length === 0 ? (
          <div className="text-center py-20 text-muted-foreground">
            <Building2 size={40} className="mx-auto mb-4 opacity-40" />
            <p>No properties match your filters.</p>
          </div>
        ) : (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {filtered.map(p => (
              <PropertyCard key={p.id} p={p}
                onClick={() => { setSelectedProperty(p); setPage("detail"); }}
                favorited={favorites.includes(p.id)} onFav={() => toggleFav(p.id)} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Detail ───────────────────────────────────────────────────────────────────

function DetailPage({ property, setPage }: { property: Property | null; setPage: (p: Page) => void }) {
  const { auth } = useAuth();
  const [tab, setTab] = useState<"overview" | "schedule">("overview");
  const [visitDate, setVisitDate] = useState("");
  const [visitTime, setVisitTime] = useState("");
  const [booked, setBooked] = useState(false);

  if (!property) return (
    <div className="min-h-screen pt-24 flex items-center justify-center">
      <button onClick={() => setPage("listings")} className="text-primary flex items-center gap-2">
        <ArrowRight className="rotate-180" size={16} />Back to listings
      </button>
    </div>
  );

  const p = property;

  return (
    <div className="min-h-screen pt-20">
      <div className="relative h-[50vh] bg-muted overflow-hidden">
        <img src={p.image} alt={p.title} className="w-full h-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-t from-black/55 to-transparent" />
        <div className="absolute bottom-6 left-6 right-6">
          <button onClick={() => setPage("listings")}
            className="text-white/80 text-sm flex items-center gap-1 mb-3 hover:text-white transition-colors">
            <ArrowRight className="rotate-180" size={14} />All listings
          </button>
          <h1 className="text-3xl md:text-4xl text-white font-['Playfair_Display']">{p.title}</h1>
          <p className="text-white/80 flex items-center gap-1 mt-1 text-sm"><MapPin size={13} />{p.district}, {p.city}</p>
        </div>
      </div>
      <div className="max-w-6xl mx-auto px-6 py-10 grid md:grid-cols-3 gap-10">
        <div className="md:col-span-2">
          <div className="flex gap-1 mb-8 bg-muted rounded-lg p-1 w-fit">
            {(["overview", "schedule"] as const).map(t => (
              <button key={t} onClick={() => setTab(t)}
                className={`px-5 py-2 rounded text-sm font-medium capitalize transition-all ${tab === t ? "bg-card shadow text-foreground" : "text-muted-foreground hover:text-foreground"}`}>
                {t === "schedule" ? "Book a Visit" : "Overview"}
              </button>
            ))}
          </div>
          {tab === "overview" && (
            <div>
              <div className="grid grid-cols-4 gap-4 mb-8">
                {[
                  { label: "Bedrooms", val: p.bedrooms, icon: <BedDouble size={18} /> },
                  { label: "Bathrooms", val: p.bathrooms, icon: <Bath size={18} /> },
                  { label: "Sq Ft", val: p.sqft.toLocaleString(), icon: <Building2 size={18} /> },
                  { label: "Rating", val: `${p.rating} ★`, icon: <Star size={18} /> },
                ].map(({ label, val, icon }) => (
                  <div key={label} className="bg-card rounded-lg p-4 border border-border text-center">
                    <div className="text-muted-foreground flex justify-center mb-1">{icon}</div>
                    <div className="font-semibold">{val}</div>
                    <div className="text-xs text-muted-foreground">{label}</div>
                  </div>
                ))}
              </div>
              <div className="mb-6">
                <h3 className="font-['Playfair_Display'] text-lg font-semibold mb-3">About this property</h3>
                <p className="text-muted-foreground text-sm leading-relaxed">
                  This {p.type} in {p.district} offers modern living at its finest. Featuring {p.bedrooms} spacious bedroom{p.bedrooms > 1 ? "s" : ""},
                  {p.bathrooms} bathroom{p.bathrooms > 1 ? "s" : ""}, and {p.sqft.toLocaleString()} sq ft of well-designed space.
                  Located in one of {p.city}'s most sought-after neighbourhoods, with easy access to schools, hospitals, shopping centres, and major transport routes.
                </p>
              </div>
              <div>
                <h3 className="font-['Playfair_Display'] text-lg font-semibold mb-3">Amenities</h3>
                <div className="flex flex-wrap gap-2">
                  {p.amenities.map(a => (
                    <span key={a} className="flex items-center gap-1.5 bg-muted text-foreground text-xs px-3 py-1.5 rounded-full">
                      <CheckCircle2 size={12} className="text-primary" />{a}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          )}
          {tab === "schedule" && (
            <div className="max-w-md">
              <h3 className="font-['Playfair_Display'] text-lg font-semibold mb-5">Book a Site Visit</h3>
              {!auth.isAuthenticated ? (
                <div className="bg-muted rounded-xl p-6 text-center border border-border">
                  <Lock size={32} className="mx-auto mb-3 text-muted-foreground" />
                  <p className="text-sm font-medium mb-1">Sign in to book a visit</p>
                  <p className="text-xs text-muted-foreground mb-4">Create a free account to schedule property visits.</p>
                  <button onClick={() => setPage("login")}
                    className="bg-primary text-primary-foreground px-6 py-2 rounded text-sm font-medium hover:opacity-90 transition-opacity">
                    Sign In
                  </button>
                </div>
              ) : booked ? (
                <div className="bg-green-50 border border-green-200 rounded-xl p-6 text-center">
                  <CheckCircle2 size={40} className="text-green-600 mx-auto mb-3" />
                  <h4 className="font-semibold text-green-800 mb-1">Visit Confirmed!</h4>
                  <p className="text-green-700 text-sm">
                    Your visit to <strong>{p.title}</strong> is booked for {visitDate} at {visitTime}.
                  </p>
                  <button onClick={() => { setBooked(false); setVisitDate(""); setVisitTime(""); }}
                    className="mt-4 text-xs text-green-700 underline">Book another date</button>
                </div>
              ) : (
                <div className="space-y-4">
                  <div>
                    <label className="text-sm font-medium block mb-1.5">Preferred Date</label>
                    <input type="date" value={visitDate} onChange={e => setVisitDate(e.target.value)}
                      min={new Date().toISOString().split("T")[0]}
                      className="w-full bg-input-background border border-border rounded px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
                  </div>
                  <div>
                    <label className="text-sm font-medium block mb-1.5">Preferred Time</label>
                    <select value={visitTime} onChange={e => setVisitTime(e.target.value)}
                      className="w-full bg-input-background border border-border rounded px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring">
                      <option value="">Select a time</option>
                      {["9:00 AM","10:00 AM","11:00 AM","2:00 PM","3:00 PM","4:00 PM"].map(t => <option key={t}>{t}</option>)}
                    </select>
                  </div>
                  <textarea rows={3} placeholder="Any questions for the host?"
                    className="w-full bg-input-background border border-border rounded px-3 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-ring" />
                  <button onClick={() => { if (visitDate && visitTime) setBooked(true); }}
                    disabled={!visitDate || !visitTime}
                    className="w-full bg-primary text-primary-foreground py-3 rounded font-medium text-sm disabled:opacity-40 hover:opacity-90 transition-opacity">
                    Confirm Visit
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
        <div>
          <div className="bg-card rounded-xl border border-border p-6 sticky top-24">
            <div className="mb-4">
              <span className="text-2xl font-bold text-primary">KSh {p.price.toLocaleString()}</span>
              <span className="text-muted-foreground text-sm">/month</span>
            </div>
            {p.matchScore && (
              <div className="bg-accent/20 rounded-lg p-3 mb-4 flex items-center gap-3">
                <Sparkles size={18} className="text-accent shrink-0" />
                <div>
                  <p className="text-xs font-semibold">Haven Match Score</p>
                  <div className="flex items-center gap-2 mt-0.5">
                    <div className="flex-1 h-1.5 bg-muted rounded-full">
                      <div className="h-full bg-accent rounded-full" style={{ width: `${p.matchScore}%` }} />
                    </div>
                    <span className="text-sm font-bold text-accent">{p.matchScore}%</span>
                  </div>
                </div>
              </div>
            )}
            <div className="border-t border-border pt-4 mb-4">
              <p className="text-xs text-muted-foreground mb-2">Hosted by</p>
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-full bg-primary flex items-center justify-center text-primary-foreground text-sm font-medium">
                  {p.host.charAt(0)}
                </div>
                <div>
                  <p className="text-sm font-medium">{p.host}</p>
                  <div className="flex items-center gap-1">
                    <Star size={11} fill="#C8A96E" stroke="none" />
                    <span className="text-xs text-muted-foreground">{p.rating} · {p.reviews} reviews</span>
                  </div>
                </div>
              </div>
            </div>
            <button onClick={() => setTab("schedule")}
              className="w-full bg-primary text-primary-foreground py-3 rounded font-medium text-sm hover:opacity-90 transition-opacity mb-2">
              Book a Visit
            </button>
            <button className="w-full border border-border py-3 rounded font-medium text-sm hover:bg-muted transition-colors flex items-center justify-center gap-2">
              <Phone size={14} />Contact Host
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Survey ───────────────────────────────────────────────────────────────────

function SurveyPage({ setPage }: { setPage: (p: Page) => void }) {
  const [step, setStep] = useState(0);
  const [answers, setAnswers] = useState<Record<number, string>>({});
  const [done, setDone] = useState(false);

  const questions = [
    { q: "What city are you moving to?", opts: ["Nairobi", "Mombasa", "Kisumu", "Nakuru", "Eldoret"] },
    { q: "What's your monthly budget?", opts: ["Under KSh 20,000", "KSh 20,000–40,000", "KSh 40,000–70,000", "KSh 70,000–100,000", "Over KSh 100,000"] },
    { q: "What type of property are you looking for?", opts: ["Studio apartment", "1–2 bedroom apartment", "3+ bedroom apartment", "House with garden", "Villa / executive"] },
    { q: "How important is proximity to work/school?", opts: ["Very important (under 5 km)", "Moderate (5–15 km)", "Not a priority"] },
    { q: "Which amenities matter most to you?", opts: ["Parking & security", "Gym & pool", "Reliable WiFi & power backup", "Green spaces & quiet", "Shopping & nightlife nearby"] },
  ];

  const choose = (opt: string) => {
    const next = { ...answers, [step]: opt };
    setAnswers(next);
    if (step < questions.length - 1) setStep(step + 1);
    else setDone(true);
  };

  return (
    <div className="min-h-screen pt-20 bg-secondary">
      <div className="max-w-2xl mx-auto px-6 py-16">
        <div className="text-center mb-10">
          <div className="inline-flex items-center gap-2 bg-accent/20 text-accent-foreground text-xs px-3 py-1.5 rounded-full mb-4 font-medium">
            <Sparkles size={12} className="text-accent" />Haven Match Survey
          </div>
          <h1 className="text-3xl md:text-4xl font-['Playfair_Display'] mb-3">
            {done ? "Your Matches Are Ready!" : "Let's Find Your Perfect Home"}
          </h1>
          <p className="text-muted-foreground text-sm">{done ? "Based on your answers, we've curated the best properties for you." : `Question ${step + 1} of ${questions.length}`}</p>
        </div>
        <div className="bg-muted rounded-full h-1.5 mb-8 overflow-hidden">
          <div className="h-full bg-accent rounded-full transition-all duration-500" style={{ width: `${done ? 100 : (step / questions.length) * 100}%` }} />
        </div>
        {!done ? (
          <div className="bg-card rounded-2xl border border-border p-8">
            <h2 className="text-xl font-['Playfair_Display'] font-semibold mb-6">{questions[step].q}</h2>
            <div className="space-y-3">
              {questions[step].opts.map(opt => (
                <button key={opt} onClick={() => choose(opt)}
                  className={`w-full text-left px-5 py-3.5 rounded-lg border text-sm transition-all ${answers[step] === opt ? "border-primary bg-primary/5 text-primary font-medium" : "border-border hover:border-primary/40 hover:bg-muted"}`}>
                  <span className="flex items-center justify-between">{opt}<ChevronRight size={14} className="text-muted-foreground" /></span>
                </button>
              ))}
            </div>
            {step > 0 && (
              <button onClick={() => setStep(step - 1)} className="mt-4 text-xs text-muted-foreground hover:text-foreground transition-colors">
                ← Previous question
              </button>
            )}
          </div>
        ) : (
          <div>
            <div className="bg-card rounded-2xl border border-border p-6 mb-6">
              <h3 className="font-['Playfair_Display'] text-lg font-semibold mb-4 flex items-center gap-2">
                <Sparkles size={16} className="text-accent" />Your Top Matches
              </h3>
              {PROPERTIES.filter(p => p.available && p.approved).slice(0, 3).map((p, i) => (
                <div key={p.id} className="flex items-center gap-4 py-3.5 border-b border-border last:border-0">
                  <span className="text-lg font-bold text-muted-foreground w-6 text-center">{i + 1}</span>
                  <img src={p.image} alt={p.title} className="w-14 h-14 rounded-lg object-cover" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold truncate">{p.title}</p>
                    <p className="text-xs text-muted-foreground">{p.district}, {p.city} · KSh {p.price.toLocaleString()}/mo</p>
                  </div>
                  <div className="text-right">
                    <span className="text-base font-bold text-accent">{p.matchScore}%</span>
                    <p className="text-xs text-muted-foreground">match</p>
                  </div>
                </div>
              ))}
            </div>
            <div className="flex gap-3">
              <button onClick={() => setPage("listings")}
                className="flex-1 bg-primary text-primary-foreground py-3 rounded font-medium text-sm hover:opacity-90 transition-opacity">
                View All Matches
              </button>
              <button onClick={() => { setStep(0); setAnswers({}); setDone(false); }}
                className="px-6 border border-border py-3 rounded font-medium text-sm hover:bg-muted transition-colors">
                Retake
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Dashboard ────────────────────────────────────────────────────────────────

function DashboardPage({ setPage }: { setPage: (p: Page) => void }) {
  const { auth } = useAuth();
  const [activeTab, setActiveTab] = useState<"overview" | "bookings" | "saved" | "profile">("overview");
  const [selectedProperty, setSelectedProperty] = useState<Property | null>(null);

  if (!auth.isAuthenticated) {
    return (
      <div className="min-h-screen pt-24 flex flex-col items-center justify-center gap-4 bg-secondary">
        <Lock size={40} className="text-muted-foreground" />
        <h2 className="text-xl font-['Playfair_Display'] font-semibold">Sign in required</h2>
        <p className="text-muted-foreground text-sm">Please sign in to access your dashboard.</p>
        <button onClick={() => setPage("login")} className="bg-primary text-primary-foreground px-6 py-2.5 rounded text-sm font-medium">Sign In</button>
      </div>
    );
  }

  const user = auth.user!;
  const bookings = [
    { property: "Serene Garden Apartment", district: "Kilimani", date: "15 Jul 2025", time: "10:00 AM", status: "confirmed" },
    { property: "Modern Studio in Westlands", district: "Westlands", date: "18 Jul 2025", time: "2:00 PM", status: "pending" },
    { property: "Coastal Villa with Ocean View", district: "Nyali, Mombasa", date: "22 Jul 2025", time: "11:00 AM", status: "confirmed" },
  ];

  return (
    <div className="min-h-screen pt-20 bg-secondary">
      <div className="max-w-7xl mx-auto px-6 py-10">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-3xl font-['Playfair_Display'] font-semibold mb-1">
              Good morning, {user.name.split(" ")[0]}
            </h1>
            <p className="text-muted-foreground text-sm flex items-center gap-2">
              <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full font-medium capitalize
                ${user.role === "admin" ? "bg-purple-100 text-purple-700" :
                  user.role === "host" ? "bg-blue-100 text-blue-700" :
                  "bg-green-100 text-green-700"}`}>
                <UserCheck size={10} />{user.role}
              </span>
              {user.verified && <span className="text-xs text-green-600 flex items-center gap-1"><ShieldCheck size={11} />Verified</span>}
            </p>
          </div>
          <button onClick={() => setPage("survey")}
            className="hidden md:flex items-center gap-2 bg-primary text-primary-foreground px-4 py-2.5 rounded text-sm font-medium hover:opacity-90 transition-opacity">
            <Sparkles size={15} />Update Survey
          </button>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          {[
            { label: "Saved Properties", val: "8", icon: <Heart size={18} />, change: "+2 this week" },
            { label: "Visits Booked", val: "3", icon: <Clock size={18} />, change: "1 upcoming" },
            { label: "Haven Score", val: "87%", icon: <Sparkles size={18} />, change: "Updated today" },
            { label: "Applications", val: "2", icon: <TrendingUp size={18} />, change: "1 pending" },
          ].map(({ label, val, icon, change }) => (
            <div key={label} className="bg-card rounded-xl border border-border p-5">
              <div className="text-muted-foreground mb-3">{icon}</div>
              <div className="text-2xl font-bold mb-0.5">{val}</div>
              <div className="text-xs text-muted-foreground">{label}</div>
              <div className="text-xs text-accent mt-1.5">{change}</div>
            </div>
          ))}
        </div>

        <div className="flex gap-1 bg-card border border-border rounded-lg p-1 w-fit mb-6">
          {(["overview", "bookings", "saved", "profile"] as const).map(tab => (
            <button key={tab} onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 rounded text-sm font-medium capitalize transition-all ${activeTab === tab ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
              {tab}
            </button>
          ))}
        </div>

        {activeTab === "overview" && (
          <div className="grid md:grid-cols-3 gap-6">
            <div className="md:col-span-2 bg-card rounded-xl border border-border p-6">
              <h3 className="font-['Playfair_Display'] text-base font-semibold mb-4">Recent Activity</h3>
              <div className="space-y-4">
                {[
                  { action: "Saved Coastal Villa with Ocean View", time: "2 hours ago", type: "save" },
                  { action: "Booked visit to Serene Garden Apartment", time: "Yesterday", type: "booking" },
                  { action: "Completed Haven Match Survey", time: "3 days ago", type: "survey" },
                  { action: "Account verified via OTP", time: "5 days ago", type: "account" },
                ].map(({ action, time, type }) => (
                  <div key={action} className="flex items-start gap-3 text-sm">
                    <div className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 mt-0.5 ${
                      type === "save" ? "bg-red-100 text-red-600" : type === "booking" ? "bg-blue-100 text-blue-600" :
                      type === "survey" ? "bg-amber-100 text-amber-600" : "bg-green-100 text-green-600"}`}>
                      {type === "save" ? <Heart size={13} /> : type === "booking" ? <Clock size={13} /> :
                       type === "survey" ? <Sparkles size={13} /> : <UserCheck size={13} />}
                    </div>
                    <div className="flex-1">
                      <p className="text-foreground">{action}</p>
                      <p className="text-xs text-muted-foreground mt-0.5">{time}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="bg-card rounded-xl border border-border p-6">
              <h3 className="font-['Playfair_Display'] text-base font-semibold mb-4">Haven Match Profile</h3>
              <div className="space-y-3">
                {[
                  { label: "Budget fit", val: 90 }, { label: "Location match", val: 85 },
                  { label: "Amenity match", val: 78 }, { label: "Lifestyle fit", val: 94 },
                ].map(({ label, val }) => (
                  <div key={label}>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="text-muted-foreground">{label}</span>
                      <span className="font-medium">{val}%</span>
                    </div>
                    <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                      <div className="h-full bg-accent rounded-full" style={{ width: `${val}%` }} />
                    </div>
                  </div>
                ))}
              </div>
              <button onClick={() => setPage("survey")}
                className="w-full mt-5 text-xs text-primary font-medium border border-primary/30 rounded py-2 hover:bg-primary/5 transition-colors">
                Retake Survey
              </button>
            </div>
          </div>
        )}

        {activeTab === "bookings" && (
          <div className="bg-card rounded-xl border border-border overflow-hidden">
            <div className="px-6 py-4 border-b border-border"><h3 className="font-['Playfair_Display'] font-semibold">Scheduled Visits</h3></div>
            <div className="divide-y divide-border">
              {bookings.map(({ property, district, date, time, status }) => (
                <div key={property} className="px-6 py-4 flex items-center gap-4">
                  <div className="flex-1">
                    <p className="text-sm font-medium">{property}</p>
                    <p className="text-xs text-muted-foreground mt-0.5 flex items-center gap-1"><MapPin size={11} />{district}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm">{date}</p>
                    <p className="text-xs text-muted-foreground">{time}</p>
                  </div>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium ${status === "confirmed" ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"}`}>
                    {status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {activeTab === "saved" && (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {PROPERTIES.slice(0, 4).map(p => (
              <PropertyCard key={p.id} p={p}
                onClick={() => { setSelectedProperty(p); setPage("detail"); }}
                favorited={true} onFav={() => {}} />
            ))}
          </div>
        )}

        {activeTab === "profile" && (
          <div className="max-w-lg bg-card rounded-xl border border-border p-8">
            <div className="flex items-center gap-4 mb-8">
              <div className="w-16 h-16 rounded-full bg-primary flex items-center justify-center text-primary-foreground text-2xl font-bold">
                {user.name.charAt(0)}
              </div>
              <div>
                <h3 className="font-semibold">{user.name}</h3>
                <p className="text-sm text-muted-foreground">{user.email}</p>
                <span className={`text-xs px-2 py-0.5 rounded-full mt-1 inline-block font-medium capitalize
                  ${user.role === "admin" ? "bg-purple-100 text-purple-700" : user.role === "host" ? "bg-blue-100 text-blue-700" : "bg-green-100 text-green-700"}`}>
                  {user.role === "tenant" ? "Verified Tenant" : user.role === "host" ? "Verified Host" : "Administrator"}
                </span>
              </div>
            </div>
            <div className="space-y-4">
              {[
                { label: "Full Name", val: user.name },
                { label: "Email", val: user.email },
                { label: "Phone", val: user.phone },
                { label: "ID Number", val: "••••••••••" },
              ].map(({ label, val }) => (
                <div key={label}>
                  <label className="text-xs text-muted-foreground block mb-1">{label}</label>
                  <input defaultValue={val}
                    className="w-full bg-input-background border border-border rounded px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring" />
                </div>
              ))}
              <button className="bg-primary text-primary-foreground px-6 py-2.5 rounded text-sm font-medium hover:opacity-90 transition-opacity">
                Save Changes
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Admin Dashboard ──────────────────────────────────────────────────────────

function AdminPage({ setPage }: { setPage: (p: Page) => void }) {
  const { auth } = useAuth();
  const [tab, setTab] = useState<"overview" | "listings" | "users" | "bookings">("overview");
  const [listings, setListings] = useState(PROPERTIES);

  if (!auth.isAuthenticated || auth.user?.role !== "admin") {
    return (
      <div className="min-h-screen pt-24 flex flex-col items-center justify-center gap-4 bg-secondary">
        <Shield size={40} className="text-muted-foreground" />
        <h2 className="text-xl font-['Playfair_Display'] font-semibold">Admin access only</h2>
        <p className="text-muted-foreground text-sm">Use admin@havenlink.co.ke / Admin123 to access this panel.</p>
        <button onClick={() => setPage("login")} className="bg-primary text-primary-foreground px-6 py-2.5 rounded text-sm font-medium">Sign In as Admin</button>
      </div>
    );
  }

  const toggleApproval = (id: number) =>
    setListings(ls => ls.map(l => l.id === id ? { ...l, approved: !l.approved } : l));

  const users = [
    { name: "Amina Kamau", email: "amina@example.com", role: "tenant", status: "active", joined: "2 Jun 2025" },
    { name: "Deo Otieno", email: "deo@example.com", role: "host", status: "active", joined: "14 May 2025" },
    { name: "Beatrice Mwangi", email: "beatrice@example.com", role: "tenant", status: "pending", joined: "1 Jul 2025" },
    { name: "Fatuma Ali", email: "fatuma@example.com", role: "host", status: "pending", joined: "3 Jul 2025" },
    { name: "Peter Njoroge", email: "peter@example.com", role: "host", status: "active", joined: "20 Apr 2025" },
  ];

  const adminBookings = [
    { id: "BK001", tenant: "Amina Kamau", property: "Serene Garden Apartment", date: "15 Jul 2025", status: "confirmed" },
    { id: "BK002", tenant: "Beatrice Mwangi", property: "Modern Studio in Westlands", date: "18 Jul 2025", status: "pending" },
    { id: "BK003", tenant: "John Doe", property: "Lakeside Family Home", date: "20 Jul 2025", status: "confirmed" },
    { id: "BK004", tenant: "Grace Wanjiku", property: "Coastal Villa", date: "22 Jul 2025", status: "cancelled" },
  ];

  return (
    <div className="min-h-screen pt-20 bg-secondary">
      <div className="max-w-7xl mx-auto px-6 py-10">
        <div className="flex items-center justify-between mb-8">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <Shield size={20} className="text-primary" />
              <h1 className="text-3xl font-['Playfair_Display'] font-semibold">Admin Panel</h1>
            </div>
            <p className="text-muted-foreground text-sm">Manage listings, users, and bookings across HavenLink</p>
          </div>
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-2 bg-card border border-border rounded-lg px-3 py-2">
              <div className="w-2 h-2 rounded-full bg-green-500" />
              <span className="text-xs text-muted-foreground">System OK</span>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          {[
            { label: "Total Listings", val: listings.length.toString(), icon: <Building2 size={18} />, color: "text-blue-600", bg: "bg-blue-50" },
            { label: "Active Users", val: "1,284", icon: <Users size={18} />, color: "text-green-600", bg: "bg-green-50" },
            { label: "Pending Approval", val: listings.filter(l => !l.approved).length.toString(), icon: <Clock size={18} />, color: "text-amber-600", bg: "bg-amber-50" },
            { label: "This Month Revenue", val: "KSh 2.4M", icon: <TrendingUp size={18} />, color: "text-purple-600", bg: "bg-purple-50" },
          ].map(({ label, val, icon, color, bg }) => (
            <div key={label} className="bg-card rounded-xl border border-border p-5">
              <div className={`w-10 h-10 ${bg} ${color} rounded-lg flex items-center justify-center mb-3`}>{icon}</div>
              <div className="text-2xl font-bold mb-0.5">{val}</div>
              <div className="text-xs text-muted-foreground">{label}</div>
            </div>
          ))}
        </div>

        <div className="flex gap-1 bg-card border border-border rounded-lg p-1 w-fit mb-6">
          {(["overview", "listings", "users", "bookings"] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-4 py-2 rounded text-sm font-medium capitalize transition-all ${tab === t ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
              {t}
            </button>
          ))}
        </div>

        {tab === "overview" && (
          <div className="grid md:grid-cols-2 gap-6">
            <div className="bg-card rounded-xl border border-border p-6">
              <h3 className="font-['Playfair_Display'] font-semibold mb-4 flex items-center gap-2">
                <Clock size={15} className="text-amber-500" />Pending Approvals
              </h3>
              {listings.filter(l => !l.approved).length === 0 ? (
                <p className="text-sm text-muted-foreground flex items-center gap-2"><CheckCircle2 size={14} className="text-green-500" />All listings approved</p>
              ) : listings.filter(l => !l.approved).map(p => (
                <div key={p.id} className="flex items-center gap-3 py-3 border-b border-border last:border-0">
                  <img src={p.image} alt={p.title} className="w-10 h-10 rounded object-cover" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{p.title}</p>
                    <p className="text-xs text-muted-foreground">{p.district} · {p.host}</p>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => toggleApproval(p.id)}
                      className="text-xs bg-green-100 text-green-700 px-2.5 py-1 rounded hover:bg-green-200 transition-colors font-medium">
                      Approve
                    </button>
                    <button className="text-xs bg-red-100 text-red-700 px-2.5 py-1 rounded hover:bg-red-200 transition-colors font-medium">
                      Reject
                    </button>
                  </div>
                </div>
              ))}
            </div>
            <div className="bg-card rounded-xl border border-border p-6">
              <h3 className="font-['Playfair_Display'] font-semibold mb-4 flex items-center gap-2">
                <Users size={15} className="text-blue-500" />Recent Registrations
              </h3>
              {users.slice(0, 4).map(({ name, email, role, status, joined }) => (
                <div key={email} className="flex items-center gap-3 py-3 border-b border-border last:border-0">
                  <div className="w-8 h-8 rounded-full bg-primary flex items-center justify-center text-primary-foreground text-xs font-bold shrink-0">
                    {name.charAt(0)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{name}</p>
                    <p className="text-xs text-muted-foreground">{email}</p>
                  </div>
                  <div className="text-right shrink-0">
                    <span className={`text-xs px-2 py-0.5 rounded-full font-medium capitalize ${role === "host" ? "bg-blue-100 text-blue-700" : "bg-green-100 text-green-700"}`}>
                      {role}
                    </span>
                    <p className="text-xs text-muted-foreground mt-0.5">{joined}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {tab === "listings" && (
          <div className="bg-card rounded-xl border border-border overflow-hidden">
            <div className="px-6 py-4 border-b border-border flex items-center justify-between">
              <h3 className="font-['Playfair_Display'] font-semibold">All Listings</h3>
              <button className="flex items-center gap-2 text-xs bg-primary text-primary-foreground px-3 py-1.5 rounded hover:opacity-90">
                <PlusCircle size={13} />Add Listing
              </button>
            </div>
            <div className="divide-y divide-border">
              {listings.map(p => (
                <div key={p.id} className="px-6 py-4 flex items-center gap-4">
                  <img src={p.image} alt={p.title} className="w-12 h-12 rounded object-cover shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{p.title}</p>
                    <p className="text-xs text-muted-foreground">{p.district}, {p.city} · {p.host}</p>
                  </div>
                  <div className="hidden md:block text-sm font-medium text-primary shrink-0">
                    KSh {p.price.toLocaleString()}
                  </div>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium shrink-0 ${p.approved ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"}`}>
                    {p.approved ? "Approved" : "Pending"}
                  </span>
                  <div className="flex gap-2 shrink-0">
                    <button onClick={() => toggleApproval(p.id)}
                      className={`text-xs px-2.5 py-1 rounded font-medium transition-colors ${p.approved ? "bg-amber-100 text-amber-700 hover:bg-amber-200" : "bg-green-100 text-green-700 hover:bg-green-200"}`}>
                      {p.approved ? "Suspend" : "Approve"}
                    </button>
                    <button className="text-xs bg-red-100 text-red-700 px-2.5 py-1 rounded hover:bg-red-200 transition-colors">
                      <Trash2 size={12} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {tab === "users" && (
          <div className="bg-card rounded-xl border border-border overflow-hidden">
            <div className="px-6 py-4 border-b border-border">
              <h3 className="font-['Playfair_Display'] font-semibold">Registered Users</h3>
            </div>
            <div className="divide-y divide-border">
              {users.map(({ name, email, role, status, joined }) => (
                <div key={email} className="px-6 py-4 flex items-center gap-4">
                  <div className="w-9 h-9 rounded-full bg-primary flex items-center justify-center text-primary-foreground text-sm font-bold shrink-0">
                    {name.charAt(0)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">{name}</p>
                    <p className="text-xs text-muted-foreground">{email}</p>
                  </div>
                  <span className={`text-xs px-2 py-0.5 rounded-full font-medium capitalize shrink-0 ${role === "host" ? "bg-blue-100 text-blue-700" : "bg-green-100 text-green-700"}`}>
                    {role}
                  </span>
                  <span className={`text-xs px-2 py-0.5 rounded-full font-medium capitalize shrink-0 ${status === "active" ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"}`}>
                    {status}
                  </span>
                  <span className="text-xs text-muted-foreground shrink-0 hidden md:block">{joined}</span>
                  <div className="flex gap-2 shrink-0">
                    <button className="text-xs bg-muted px-2.5 py-1 rounded hover:bg-secondary transition-colors font-medium">
                      <Edit3 size={12} />
                    </button>
                    <button className="text-xs bg-red-100 text-red-700 px-2.5 py-1 rounded hover:bg-red-200 transition-colors">
                      <Trash2 size={12} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {tab === "bookings" && (
          <div className="bg-card rounded-xl border border-border overflow-hidden">
            <div className="px-6 py-4 border-b border-border">
              <h3 className="font-['Playfair_Display'] font-semibold">All Bookings</h3>
            </div>
            <div className="divide-y divide-border">
              {adminBookings.map(({ id, tenant, property, date, status }) => (
                <div key={id} className="px-6 py-4 flex items-center gap-4">
                  <span className="font-mono text-xs text-muted-foreground w-12 shrink-0">{id}</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{property}</p>
                    <p className="text-xs text-muted-foreground">{tenant}</p>
                  </div>
                  <span className="text-xs text-muted-foreground shrink-0 hidden md:block">{date}</span>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium shrink-0 ${
                    status === "confirmed" ? "bg-green-100 text-green-700" :
                    status === "pending" ? "bg-amber-100 text-amber-700" :
                    "bg-red-100 text-red-700"}`}>
                    {status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Home ─────────────────────────────────────────────────────────────────────

function HomePage({ setPage }: { setPage: (p: Page) => void }) {
  const [searchCity, setSearchCity] = useState("All Cities");
  const [searchType, setSearchType] = useState("All Types");

  return (
    <div className="min-h-screen">
      <section className="relative min-h-[92vh] flex items-center overflow-hidden">
        <div className="absolute inset-0">
          <img src="https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=1600&h=900&fit=crop&auto=format"
            alt="Nairobi cityscape" className="w-full h-full object-cover" />
          <div className="absolute inset-0 bg-gradient-to-r from-primary/90 via-primary/70 to-transparent" />
        </div>
        <div className="relative max-w-7xl mx-auto px-6 py-24 grid md:grid-cols-2 gap-16 items-center">
          <div>
            <div className="inline-flex items-center gap-2 bg-white/10 border border-white/20 text-white/90 text-xs px-3 py-1.5 rounded-full mb-6 backdrop-blur-sm">
              <Sparkles size={12} />AI-Powered Tenant Matching
            </div>
            <h1 className="text-5xl md:text-6xl text-white mb-6 leading-tight">
              Find Your<br /><span className="text-accent">Perfect Home</span><br />in East Africa
            </h1>
            <p className="text-white/80 text-lg mb-8 leading-relaxed max-w-md">
              Haven Link connects tenants with verified properties using smart matching.
              Tell us what you need — we find what fits.
            </p>
            <div className="bg-card rounded-xl p-4 shadow-2xl max-w-lg">
              <div className="grid grid-cols-2 gap-3 mb-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block font-medium">City</label>
                  <select value={searchCity} onChange={e => setSearchCity(e.target.value)}
                    className="w-full bg-input-background rounded px-3 py-2 text-sm border border-border focus:outline-none focus:ring-2 focus:ring-ring">
                    {CITIES.map(c => <option key={c}>{c}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block font-medium">Type</label>
                  <select value={searchType} onChange={e => setSearchType(e.target.value)}
                    className="w-full bg-input-background rounded px-3 py-2 text-sm border border-border focus:outline-none focus:ring-2 focus:ring-ring">
                    {TYPES.map(t => <option key={t}>{t}</option>)}
                  </select>
                </div>
              </div>
              <div className="flex gap-2">
                <div className="flex-1 relative">
                  <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
                  <input placeholder="District or neighbourhood…"
                    className="w-full bg-input-background rounded pl-9 pr-3 py-2 text-sm border border-border focus:outline-none focus:ring-2 focus:ring-ring" />
                </div>
                <button onClick={() => setPage("listings")}
                  className="bg-primary text-primary-foreground px-5 py-2 rounded text-sm font-medium hover:opacity-90 flex items-center gap-2">
                  Search <ArrowRight size={14} />
                </button>
              </div>
            </div>
            <div className="flex gap-6 mt-6 text-white/70 text-sm">
              <span><strong className="text-white">2,400+</strong> listings</span>
              <span><strong className="text-white">18</strong> cities</span>
              <span><strong className="text-white">94%</strong> match accuracy</span>
            </div>
          </div>
          <div className="hidden md:block">
            <div className="bg-card/90 backdrop-blur-sm rounded-xl p-5 border border-white/10 shadow-xl">
              <div className="flex items-center justify-between mb-4">
                <h4 className="text-sm font-semibold">Haven Match Score™</h4>
                <Sparkles size={16} className="text-accent" />
              </div>
              {PROPERTIES.filter(p => p.approved).slice(0, 3).map(p => (
                <div key={p.id} className="flex items-center gap-3 py-2.5 border-b border-border last:border-0">
                  <img src={p.image} alt={p.title} className="w-10 h-10 rounded object-cover" />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-medium truncate">{p.title}</p>
                    <p className="text-xs text-muted-foreground">{p.district} · KSh {p.price.toLocaleString()}/mo</p>
                  </div>
                  <div className="flex flex-col items-end">
                    <span className="text-sm font-bold text-accent">{p.matchScore}%</span>
                    <div className="w-16 h-1.5 bg-muted rounded-full overflow-hidden mt-1">
                      <div className="h-full bg-accent rounded-full" style={{ width: `${p.matchScore}%` }} />
                    </div>
                  </div>
                </div>
              ))}
              <button onClick={() => setPage("survey")} className="w-full mt-4 text-xs text-primary font-medium flex items-center justify-center gap-1 hover:gap-2 transition-all">
                Take the survey to see your matches <ArrowRight size={12} />
              </button>
            </div>
          </div>
        </div>
      </section>

      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="text-center mb-14">
          <h2 className="text-3xl md:text-4xl mb-4">Why Tenants Choose Haven Link</h2>
          <p className="text-muted-foreground max-w-xl mx-auto">We take the guesswork out of renting.</p>
        </div>
        <div className="grid md:grid-cols-3 gap-8">
          {[
            { icon: <Sparkles className="text-accent" size={22} />, title: "AI Haven Match", desc: "Our survey algorithm matches your lifestyle and budget to properties with up to 96% compatibility." },
            { icon: <ShieldCheck className="text-accent" size={22} />, title: "Verified Hosts", desc: "Every landlord is ID-verified and every listing is physically inspected before going live." },
            { icon: <Clock className="text-accent" size={22} />, title: "Instant Scheduling", desc: "Book site visits in seconds. Get confirmations within the hour. No phone calls needed." },
          ].map(({ icon, title, desc }) => (
            <div key={title} className="bg-card rounded-xl p-8 border border-border hover:shadow-md transition-shadow">
              <div className="w-12 h-12 bg-muted rounded-lg flex items-center justify-center mb-5">{icon}</div>
              <h3 className="font-['Playfair_Display'] text-lg font-semibold mb-3">{title}</h3>
              <p className="text-muted-foreground text-sm leading-relaxed">{desc}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="bg-secondary py-20">
        <div className="max-w-7xl mx-auto px-6">
          <div className="flex items-end justify-between mb-10">
            <div>
              <h2 className="text-3xl md:text-4xl mb-2">Featured Properties</h2>
              <p className="text-muted-foreground">Hand-picked homes across East Africa</p>
            </div>
            <button onClick={() => setPage("listings")}
              className="hidden md:flex items-center gap-2 text-sm text-primary font-medium hover:gap-3 transition-all">
              View all <ArrowRight size={15} />
            </button>
          </div>
          <div className="grid md:grid-cols-3 gap-6">
            {PROPERTIES.filter(p => p.approved).slice(0, 3).map(p => (
              <PropertyCard key={p.id} p={p} onClick={() => {}} favorited={false} onFav={() => {}} />
            ))}
          </div>
        </div>
      </section>

      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="bg-primary rounded-2xl p-12 md:p-16 text-center relative overflow-hidden">
          <div className="absolute inset-0 opacity-10">
            <div className="absolute top-0 right-0 w-96 h-96 bg-accent rounded-full translate-x-1/2 -translate-y-1/2" />
            <div className="absolute bottom-0 left-0 w-64 h-64 bg-accent rounded-full -translate-x-1/2 translate-y-1/2" />
          </div>
          <div className="relative">
            <h2 className="text-3xl md:text-4xl text-primary-foreground mb-4">Ready to Find Your Haven?</h2>
            <p className="text-primary-foreground/70 mb-8 max-w-md mx-auto">
              Take our 2-minute survey and get matched with properties perfectly suited to your life.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <button onClick={() => setPage("survey")}
                className="bg-accent text-accent-foreground px-8 py-3 rounded font-medium hover:opacity-90 transition-opacity flex items-center gap-2 justify-center">
                <Sparkles size={16} />Start Haven Survey
              </button>
              <button onClick={() => setPage("register")}
                className="border border-primary-foreground/30 text-primary-foreground px-8 py-3 rounded font-medium hover:bg-white/10 transition-colors flex items-center gap-2 justify-center">
                <UserPlus size={16} />Create Account
              </button>
            </div>
          </div>
        </div>
      </section>

      <footer className="border-t border-border bg-card">
        <div className="max-w-7xl mx-auto px-6 py-12 grid md:grid-cols-4 gap-10">
          <div>
            <div className="flex items-center gap-2 mb-4">
              <div className="w-7 h-7 bg-primary rounded-sm flex items-center justify-center">
                <Home size={13} className="text-primary-foreground" />
              </div>
              <span className="font-['Playfair_Display'] font-semibold">Haven<span className="text-accent">Link</span></span>
            </div>
            <p className="text-xs text-muted-foreground leading-relaxed mb-4">
              East Africa's most trusted rental platform. AI-powered precision for tenants and landlords.
            </p>
            <div className="flex gap-3">
              {[Instagram, Twitter, Facebook].map((Icon, i) => (
                <button key={i} className="w-8 h-8 rounded bg-muted flex items-center justify-center text-muted-foreground hover:text-foreground transition-colors">
                  <Icon size={14} />
                </button>
              ))}
            </div>
          </div>
          {[
            { title: "Tenants", links: ["Search Properties", "Haven Survey", "Book a Visit", "Pay Rent"] },
            { title: "Landlords", links: ["List Your Property", "Host Dashboard", "Pricing", "Verification"] },
            { title: "Company", links: ["About Us", "Blog", "Careers", "Contact"] },
          ].map(({ title, links }) => (
            <div key={title}>
              <h4 className="text-sm font-semibold mb-4">{title}</h4>
              <ul className="space-y-2.5">
                {links.map(l => <li key={l}><a href="#" className="text-xs text-muted-foreground hover:text-foreground transition-colors">{l}</a></li>)}
              </ul>
            </div>
          ))}
        </div>
        <div className="border-t border-border px-6 py-4 max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">© 2025 HavenLink Ltd. All rights reserved.</p>
          <p className="text-xs text-muted-foreground flex items-center gap-1"><Mail size={11} />hello@havenlink.co.ke</p>
        </div>
      </footer>
    </div>
  );
}

// ─── Root ─────────────────────────────────────────────────────────────────────

export default function App() {
  const [page, setPage] = useState<Page>("home");
  const [selectedProperty, setSelectedProperty] = useState<Property | null>(null);
  const [auth, setAuth] = useState<AuthState>({ user: null, token: null, isAuthenticated: false });

  function login(user: User, token: string) {
    setAuth({ user, token, isAuthenticated: true });
  }

  function logout() {
    setAuth({ user: null, token: null, isAuthenticated: false });
  }

  return (
    <AuthContext.Provider value={{ auth, login, logout }}>
      <div className="min-h-screen bg-background" style={{ fontFamily: "'DM Sans', sans-serif" }}>
        <Nav page={page} setPage={setPage} />
        <main>
          {page === "home"     && <HomePage setPage={setPage} />}
          {page === "listings" && <ListingsPage setPage={setPage} setSelectedProperty={setSelectedProperty} />}
          {page === "detail"   && <DetailPage property={selectedProperty} setPage={setPage} />}
          {page === "survey"   && <SurveyPage setPage={setPage} />}
          {page === "login"    && <LoginPage setPage={setPage} />}
          {page === "register" && <RegisterPage setPage={setPage} />}
          {page === "otp"      && <OTPPage setPage={setPage} />}
          {page === "forgot"   && <ForgotPasswordPage setPage={setPage} />}
          {page === "dashboard"&& <DashboardPage setPage={setPage} />}
          {page === "admin"    && <AdminPage setPage={setPage} />}
        </main>
      </div>
    </AuthContext.Provider>
  );
}
